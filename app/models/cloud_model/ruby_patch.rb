module CloudModel
  # Brings the RVM Ruby of running guests onto a new patch release without a
  # redeploy — for the security releases, which come with public exploit code
  # and a fleet that cannot be rebuilt the same day.
  #
  # The guests get their Ruby from the template (RubyComponentWorker, RVM
  # under /usr/local/rvm). Passenger's `passenger_free_ruby` takes the first
  # ruby in the PATH of the app user's login shell, where RVM honours the
  # application's `.ruby-version` (pinned to the template's Ruby by the web
  # image build) and falls back to the default alias; the job and rake units
  # run `rvm default do`. So a patch sets both: the default alias and the
  # `.ruby-version` of every application, then restarts the Passenger apps
  # and the units, and checks the interpreters the processes really run.
  # Within one minor line (3.4.x) the ABI is stable, so the applications'
  # bundles (bundle/ruby/3.4.0) keep working on the new interpreter and
  # nothing has to be rebuilt.
  #
  # Per (os, arch) the Ruby is compiled once on the build host, in a clone of
  # a finished guest template of that os/arch ({Workers::RubyBuildWorker}),
  # committed as a small ZFS volume and synced host to host the way template
  # volumes travel ({Mixins::ZfsDatasetSync}, direct over the private
  # network); every guest then gets it unpacked
  # into /usr/local/rvm, bundler in the versions its applications are locked
  # to, a `bundle check` per application — only when all of them pass does
  # the default alias switch, the `.ruby-version` of each application, a
  # Passenger app restart (a cold start of the app) and a restart of the job
  # units. The old Ruby stays: it is the rollback.
  #
  # Driven by `rake cloudmodel:guest:patch_ruby RUBY=<version>` (dry run
  # unless CONFIRM=1).
  class RubyPatch
    include CloudModel::Mixins::ZfsDatasetSync

    RVM = '/usr/local/rvm/bin/rvm'
    RVM_PATH = '/usr/local/rvm'

    attr_reader :version, :output

    # @param version [String] the exact Ruby to install, e.g. "3.4.13"
    # @param rvm_update [Boolean] run `rvm get master` in the build system
    #   first (when RVM refuses the version as unknown)
    def initialize version:, rvm_update: false, output: $stdout
      raise ArgumentError, "RUBY must be a full version like 3.4.13, got #{version.inspect}" unless version.to_s =~ /\A\d+\.\d+\.\d+\z/
      @version = version.to_s
      @rvm_update = rvm_update
      @output = output
    end

    def ruby_name
      "ruby-#{version}"
    end

    def ruby_bin
      "#{RVM_PATH}/rubies/#{ruby_name}/bin/ruby"
    end

    # Guests that run a Ruby from the template: any service whose components
    # include a ruby — an nginx service with Passenger or Capistrano support,
    # a CI runner with a ruby toolchain, …
    def self.guests_with_ruby guests
      guests.select do |g|
        g.services.any? { |s| s.components_needed.any? { |c| c.to_s =~ /\Aruby(@|\z)/ } }
      end
    end

    # What the guest runs right now.
    # @return [Hash] default: RUBY_VERSION of `rvm default`, installed: [ruby
    #   names], apps: [{dir:, bundled_with:, ruby_version:}] (the
    #   applications under /var/www/<app>/current with the bundler their lock
    #   names and their `.ruby-version`), passenger_running: / other_running:
    #   / running: [versions] (RUBY_VERSION of the interpreters the app
    #   user's ruby processes execute — Passenger apps; job workers and rake
    #   services; both), units: [systemd units to restart],
    #   os:, arch: (as dpkg names them)
    def inventory guest
      success, data = guest.exec "bash -c #{INVENTORY_SCRIPT.shellescape}"
      raise "inventory failed: #{data.to_s.lines.last}" unless success
      result = { installed: [], apps: [], passenger_running: [], other_running: [], units: [] }
      data.to_s.each_line do |line|
        key, _, value = line.strip.partition('=')
        case key
        when 'default' then result[:default] = value.presence
        when 'installed' then result[:installed] = value.split
        when 'app'
          dir, bundled, pinned = value.split('|', 3)
          result[:apps] << { dir: dir, bundled_with: bundled.presence, ruby_version: pinned.to_s.sub(/\Aruby-/, '').presence }
        when 'passenger_running' then result[:passenger_running] = value.split
        when 'other_running' then result[:other_running] = value.split
        when 'units' then result[:units] = value.split
        when 'os' then result[:os] = value
        when 'arch' then result[:arch] = value
        end
      end
      result[:running] = (result[:passenger_running] + result[:other_running]).uniq.sort
      result
    end

    def up_to_date? inv
      inv[:default] == version &&
        inv[:apps].all? { |a| a[:ruby_version].nil? || a[:ruby_version] == version } &&
        inv[:running].all? { |v| v == version }
    end

    # A patch moves within one minor line (3.4.x → 3.4.13): the bundles are
    # ABI-compatible there and nowhere else. A guest on another line is not
    # touched.
    def same_line? inv
      inv[:default].to_s.split('.').first(2) == version.split('.').first(2)
    end

    # The ruby volume of this release for an os/arch on `host`: the RVM
    # directories of the one Ruby (rubies/, gems/, environments/, wrappers/),
    # committed with a @ready snapshot like a template volume.
    def volume_on host, os, arch
      CloudModel::BuildZfsVolume.new host, "#{CloudModel.config.build_dataset}/ruby/#{version}/#{os}-#{arch}",
        mountpoint: "/cloud/build/ruby/#{version}/#{os}-#{arch}"
    end

    # @param guests [Array<Guest>] running guests with a Ruby (see .guests_with_ruby)
    # @param dry_run [Boolean] inventory and plan only
    # @return [Hash] `{ patched:, current:, skipped:, failed: }` counts
    def patch! guests, dry_run: true
      counts = { patched: 0, current: 0, skipped: 0, failed: 0 }
      groups = guests.sort_by { |g| [g.host.name, g.name] }.group_by { |g| [g.os_version, g.host.arch] }

      groups.each do |(os, arch), group|
        output.puts "\n== #{os} #{arch}: #{group.size} guest(s)"
        inventories = {}
        group.each do |guest|
          print_prefix guest
          begin
            inv = inventory(guest)
            state = state_label inv
            apps = inv[:apps].map { |a| "#{a[:dir].sub('/var/www/', '')} (.ruby-version #{a[:ruby_version] || '-'}, bundler #{a[:bundled_with] || '?'})" }
            running = inv[:running].any? ? "running #{inv[:running] * ' '}" : 'no ruby process'
            output.puts "#{state}; #{apps.any? ? apps * ', ' : 'no application'}; #{running}; installed #{inv[:installed] * ' '}"
            if inv[:arch].present? && inv[:arch] != arch
              raise "guest reports arch #{inv[:arch]}, host is #{arch} — leaving it out"
            end
            unless same_line? inv
              counts[:skipped] += 1
              output.puts "    \e[33mskipped\e[39m: #{inv[:default] || 'no default ruby'} is not on the #{version.split('.').first(2) * '.'} line — not a patch, left alone"
              next
            end
            inventories[guest] = inv
          rescue => e
            counts[:failed] += 1
            inventories.delete guest
            output.puts "\e[31mFAILED\e[39m (#{e.message[0, 160]})"
          end
        end

        todo = inventories.reject { |_g, inv| up_to_date?(inv) }.keys
        counts[:current] += inventories.size - todo.size
        next if todo.empty?

        hosts = todo.map(&:host).uniq
        if dry_run
          build_host = CloudModel::Host.build_host(arch)
          template = build_template os, arch
          if build_host && template
            ready = volume_on(build_host, os, arch).ready?
            to_sync, synced = (hosts - [build_host]).partition { |h| !volume_on(h, os, arch).ready? }
            plan = [ready ? "reuse the #{ruby_name} volume on #{build_host.name}" : "compile #{ruby_name} on #{build_host.name} in a clone of template #{template.id} (#{template.template_type&.components&.join(',')})"]
            plan << "sync it to #{to_sync.map(&:name).join(', ')}" if to_sync.any?
            plan << "reuse the copy already on #{synced.map(&:name).join(', ')}" if synced.any?
            output.puts "  would #{plan.join(', ')}, then patch #{todo.size} guest(s)"
          else
            output.puts "  \e[31mno #{build_host ? 'finished template with a ruby' : 'build host'} for #{os} #{arch}\e[39m — #{todo.size} guest(s) stay"
          end
          next
        end

        begin
          build_host = ensure_volume os, arch
        rescue => e
          counts[:failed] += todo.size
          output.puts "  \e[31mbuild FAILED\e[39m: #{e.message.lines.last.to_s.strip[0, 200]}"
          next
        end

        synced = hosts.select do |host|
          begin
            ensure_volume_on host, build_host, os, arch
            true
          rescue => e
            counts[:failed] += todo.count { |g| g.host == host }
            output.puts "  \e[31msync to #{host.name} FAILED\e[39m: #{e.message.lines.last.to_s.strip[0, 200]}"
            false
          end
        end

        todo.select { |g| synced.include? g.host }.each do |guest|
          print_prefix guest
          begin
            note = patch_guest guest, inventories[guest], os, arch
            counts[:patched] += 1
            output.puts "\e[32m#{note}\e[39m"
          rescue => e
            counts[:failed] += 1
            output.puts "\e[31mFAILED\e[39m (#{e.message.lines.last.to_s.strip[0, 200]})"
            inv = inventories[guest]
            output.puts "    rollback if it switched: #{RVM} alias create default ruby-#{inv[:default]}; #{inv[:apps].map { |a| "echo #{a[:ruby_version] || inv[:default]} > #{a[:dir]}/.ruby-version" } * '; '}; passenger-config restart-app / --ignore-app-not-running; systemctl try-restart #{inv[:units] * ' '}"
          end
        end
      end
      counts
    end

    private

    INVENTORY_SCRIPT = <<~SH
      RVM=#{RVM}
      echo "default=$($RVM default do ruby -e 'print RUBY_VERSION' 2>/dev/null)"
      echo "installed=$(ls #{RVM_PATH}/rubies 2>/dev/null | grep '^ruby-' | tr '\\n' ' ')"
      for c in /var/www/*/current; do
        [ -f "$c/Gemfile.lock" ] || continue
        echo "app=$c|$(awk '/^BUNDLED WITH/ { getline; gsub(/ /, ""); print }' "$c/Gemfile.lock")|$(cat "$c/.ruby-version" 2>/dev/null | tr -d '[:space:]')"
      done
      rubies() { grep -o 'rubies/ruby-[0-9.]*/' | sed 's#rubies/ruby-##; s#/##' | sort -u | tr '\\n' ' '; }
      pass=""; other=""
      for p in $(ps -u www -o pid= 2>/dev/null); do
        e=$(readlink /proc/$p/exe 2>/dev/null) || continue
        if ps -o args= -p $p 2>/dev/null | grep -q '^Passenger'; then pass="$pass $e"; else other="$other $e"; fi
      done
      echo "passenger_running=$(echo "$pass" | tr ' ' '\\n' | rubies)"
      echo "other_running=$(echo "$other" | tr ' ' '\\n' | rubies)"
      echo "units=$(systemctl list-units --plain --no-legend 'delayed_jobs@*.service' 'rake-*.service' monitoring.service 2>/dev/null | awk '{ print $1 }' | tr '\\n' ' ')"
      echo "os=$(. /etc/os-release; echo $ID-$VERSION_ID)"
      echo "arch=$(dpkg --print-architecture)"
    SH

    # "on 3.4.13", "3.4.8 → 3.4.13", or — switched already, but a process
    # still runs the old interpreter (a unit restart that timed out) — what
    # is left to restart.
    def state_label inv
      return "\e[32mon #{version}\e[39m" if up_to_date?(inv)
      stale = inv[:running].reject { |v| v == version }
      if inv[:default] == version && inv[:apps].all? { |a| a[:ruby_version].nil? || a[:ruby_version] == version } && stale.any?
        "\e[33mswitched to #{version}, still running #{stale * ' '}\e[39m"
      else
        "#{inv[:default] || '?'} → #{version}"
      end
    end

    def print_prefix guest
      output.print "  #{guest.name} @ #{guest.host.name}: "
    end

    def installed? inv
      inv[:installed].include? ruby_name
    end

    # The newest finished guest template of the os/arch whose components
    # include a ruby — RVM and the build dependencies are in it.
    def build_template os, arch
      CloudModel::GuestTemplate.where(os_version: os, arch: arch, build_state_id: 0xf0).order(created_at: :desc).to_a.detect do |t|
        t.template_type&.components.to_a.any? { |c| c.to_s =~ /\Aruby/ }
      end
    end

    # Compiles the Ruby on the build host when its volume is not there yet.
    # @return [CloudModel::Host] the build host
    def ensure_volume os, arch
      host = CloudModel::Host.build_host(arch) or raise "no build host for arch #{arch} (CloudModel.config.build_host_name)"
      volume = volume_on host, os, arch
      if volume.ready?
        output.puts "  #{ruby_name} volume ready on #{host.name}"
      else
        template = build_template(os, arch) or raise "no finished guest template with a ruby for #{os} #{arch}"
        output.puts "  compiling #{ruby_name} on #{host.name} in a clone of template #{template.id} (several minutes) …"
        CloudModel::Workers::RvmRubyBuildWorker.new(host, template: template, version: version, volume: volume, rvm_update: @rvm_update).build!
      end
      host
    end

    # Brings the ruby volume onto `host` (zfs send/receive from the build
    # host, direct over the private network) and mounts it.
    def ensure_volume_on host, build_host, os, arch
      volume = volume_on host, os, arch
      unless volume.ready?
        output.puts "  syncing #{ruby_name} volume #{build_host.name} → #{host.name}"
        sync_zfs_dataset! build_host, host, volume.dataset_name
      end
      volume.mount!
    end

    def patch_guest guest, inv, os, arch
      host = guest.host
      unless installed? inv
        mountpoint = volume_on(host, os, arch).mountpoint
        host.exec! "tar -C #{mountpoint.shellescape} -cf - rubies gems environments wrappers | /usr/bin/lxc exec #{guest.current_lxd_container.name.shellescape} -- tar -C #{RVM_PATH} -xf -",
          "unpacking the ruby into #{guest.name} failed"
      end
      guest.exec! "bash -c #{switch_script(inv).shellescape}", "switching #{guest.name} to #{ruby_name} failed"
      # Passenger respawns the apps on the next request, the units come back
      # within seconds — give the processes a moment, then look at what the
      # app user's processes really execute.
      # On an I/O-bound host a Rails boot takes minutes, so give it up to
      # three before calling the switch failed.
      after = nil
      36.times do
        sleep 5
        after = inventory guest
        break if up_to_date?(after)
      end
      stale = after[:running].reject { |v| v == version }
      raise "guest still runs #{stale * ' '} after the switch (default #{after[:default]})" unless up_to_date?(after)
      after[:running].empty? ? 'patched (no ruby process running yet — checks on the next request)' : 'patched'
    end

    # Everything that can fail runs before anything changes: bundler in the
    # locked versions, `bundle check` per application. Then the default alias
    # and the applications' `.ruby-version`, a Passenger restart per
    # application, the job units (without waiting: a unit whose Rails boot
    # outlives systemd's start timeout on a slow host must not abort the
    # switch — the verification afterwards looks at the processes). A guest
    # that is switched already and only has processes left on the old Ruby
    # (a unit restart that timed out in an earlier run) gets just the
    # restarts it needs: the Passenger apps when a Passenger process is
    # stale, the units when another process is.
    def switch_script inv
      switched = inv[:default] == version && inv[:apps].all? { |a| a[:ruby_version] == version }
      bundlers = inv[:apps].map { |a| a[:bundled_with] }.compact.uniq
      steps = ["set -e", "test -x #{ruby_bin}"]
      unless switched
        steps += bundlers.map { |b| "#{RVM} #{ruby_name} do gem install bundler -v #{b.shellescape} --no-document >/dev/null" }
        steps += inv[:apps].map { |a| "(cd #{a[:dir].shellescape} && #{RVM} #{ruby_name} do bundle check >/dev/null) || { echo \"bundle check failed in #{a[:dir]}\"; exit 3; }" }
        steps << "#{RVM} alias create default #{ruby_name}"
        steps += inv[:apps].map { |a| "echo #{ruby_name} > #{a[:dir].shellescape}/.ruby-version" }
      end
      stale = ->(versions) { versions.any? { |v| v != version } }
      if !switched || stale.(inv[:passenger_running])
        steps += inv[:apps].map { |a| "passenger-config restart-app #{a[:dir].shellescape} --ignore-app-not-running >/dev/null 2>&1 || true" }
      end
      if !switched || stale.(inv[:other_running])
        steps += inv[:units].map { |u| "systemctl --no-block try-restart #{u.shellescape}" }
      end
      steps.join("\n") + "\n"
    end
  end
end
