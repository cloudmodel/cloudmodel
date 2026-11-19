module CloudModel
  # Brings the RVM Ruby of running guests onto a new patch release without a
  # redeploy — for the security releases, which come with public exploit code
  # and a fleet that cannot be rebuilt the same day.
  #
  # The guests get their Ruby from the template (RubyComponentWorker, RVM
  # under /usr/local/rvm); Passenger boots the interpreter named in
  # /etc/nginx/passenger.conf, the job and rake units run `rvm default do`.
  # Within one minor line (3.4.x) the ABI is stable, so the applications'
  # bundles (bundle/ruby/3.4.0) keep working on the new interpreter and
  # nothing has to be rebuilt.
  #
  # Per (os, arch) the Ruby is compiled once on the build host, in a clone of
  # a finished guest template of that os/arch ({Workers::RubyBuildWorker}),
  # and distributed through the controller to the hosts; every guest then gets the archive unpacked
  # into /usr/local/rvm, bundler in the versions its applications are locked
  # to, a `bundle check` per application — only when all of them pass does
  # the default alias switch, passenger.conf gets the new interpreter and
  # nginx reloads (a Passenger cold start), and the job units restart. The
  # old Ruby stays: Passenger's own gem (passenger_root, with the compiled
  # agent) lives in its gem dir, and it is the rollback.
  #
  # Driven by `rake cloudmodel:guest:patch_ruby RUBY=<version>` (dry run
  # unless CONFIRM=1).
  class RubyPatch
    RVM = '/usr/local/rvm/bin/rvm'
    RVM_PATH = '/usr/local/rvm'

    attr_reader :version, :output

    # @param version [String] the exact Ruby to install, e.g. "3.4.13"
    # @param rvm_update [Boolean] run `rvm get master` in the build system
    #   first (when RVM refuses the version as unknown)
    # @param local_dir [String, Pathname] where the controller caches the archives
    def initialize version:, rvm_update: false, local_dir: Rails.root.join('tmp', 'ruby_patch'), output: $stdout
      raise ArgumentError, "RUBY must be a full version like 3.4.13, got #{version.inspect}" unless version.to_s =~ /\A\d+\.\d+\.\d+\z/
      @version = version.to_s
      @rvm_update = rvm_update
      @local_dir = local_dir
      @output = output
    end

    def ruby_name
      "ruby-#{version}"
    end

    def ruby_bin
      "#{RVM_PATH}/rubies/#{ruby_name}/bin/ruby"
    end

    # Guests that run a Ruby from the template: an nginx service with
    # Passenger or Capistrano support pulls the ruby component in.
    def self.guests_with_ruby guests
      guests.select do |g|
        g.services.any? { |s| s.is_a?(CloudModel::Services::Nginx) && (s.passenger_supported || s.capistrano_supported) }
      end
    end

    # What the guest runs right now.
    # @return [Hash] default: RUBY_VERSION of `rvm default`, installed: [ruby
    #   names], passenger_ruby: interpreter path from passenger.conf (nil
    #   without the file), apps: [{dir:, bundled_with:}], units: [systemd
    #   units to restart], os:, arch: (as dpkg names them)
    def inventory guest
      success, data = guest.exec "bash -c #{INVENTORY_SCRIPT.shellescape}"
      raise "inventory failed: #{data.to_s.lines.last}" unless success
      result = { installed: [], apps: [], units: [] }
      data.to_s.each_line do |line|
        key, _, value = line.strip.partition('=')
        case key
        when 'default' then result[:default] = value.presence
        when 'installed' then result[:installed] = value.split
        when 'passenger_ruby' then result[:passenger_ruby] = value.presence
        when 'passenger_version' then result[:passenger_version] = value.presence
        when 'app'
          dir, bundled = value.split('|', 2)
          result[:apps] << { dir: dir, bundled_with: bundled.presence }
        when 'units' then result[:units] = value.split
        when 'os' then result[:os] = value
        when 'arch' then result[:arch] = value
        end
      end
      result
    end

    def up_to_date? inv
      inv[:default] == version && (inv[:passenger_ruby].nil? || inv[:passenger_ruby] == ruby_bin)
    end

    # @param guests [Array<Guest>] running guests with a Ruby (see .guests_with_ruby)
    # @param dry_run [Boolean] inventory and plan only
    # @return [Hash] `{ patched:, current:, failed: }` counts
    def patch! guests, dry_run: true
      counts = { patched: 0, current: 0, failed: 0 }
      groups = guests.sort_by { |g| [g.host.name, g.name] }.group_by { |g| [g.os_version, g.host.arch] }

      groups.each do |(os, arch), group|
        output.puts "\n== #{os} #{arch}: #{group.size} guest(s)"
        inventories = {}
        group.each do |guest|
          print_prefix guest
          begin
            inv = inventories[guest] = inventory(guest)
            state = up_to_date?(inv) ? "\e[32mon #{version}\e[39m" : "#{inv[:default] || '?'} → #{version}"
            passenger = inv[:passenger_ruby] ? "passenger #{inv[:passenger_ruby].sub("#{RVM_PATH}/rubies/", '')}" : 'no passenger.conf'
            apps = inv[:apps].map { |a| "#{a[:dir].sub('/var/www/', '')} (bundler #{a[:bundled_with] || '?'})" }
            output.puts "#{state}; #{passenger}; #{apps.any? ? apps * ', ' : 'no application'}; installed #{inv[:installed] * ' '}"
            if inv[:arch].present? && inv[:arch] != arch
              raise "guest reports arch #{inv[:arch]}, host is #{arch} — leaving it out"
            end
          rescue => e
            counts[:failed] += 1
            inventories.delete guest
            output.puts "\e[31mFAILED\e[39m (#{e.message[0, 160]})"
          end
        end

        todo = inventories.reject { |_g, inv| up_to_date?(inv) }.keys
        counts[:current] += inventories.size - todo.size
        next if todo.empty?

        if dry_run
          host = CloudModel::Host.build_host(arch)
          template = build_template os, arch
          where = host && template ? "on #{host.name} in a clone of template #{template.id} (#{template.template_type&.components&.join(',')})" : "\e[31mno #{host ? 'finished template with a ruby' : 'build host'} for #{os} #{arch}\e[39m"
          output.puts "  would compile #{ruby_name} #{where}#{' — archive cached, no compile' if File.file?(local_archive(os, arch))}, then patch #{todo.size} guest(s)"
          next
        end

        begin
          ensure_archive os, arch
        rescue => e
          counts[:failed] += todo.size
          output.puts "  \e[31mbuild FAILED\e[39m: #{e.message.lines.last.to_s.strip[0, 200]}"
          next
        end

        todo.each do |guest|
          print_prefix guest
          begin
            patch_guest guest, inventories[guest], os, arch
            counts[:patched] += 1
            output.puts "\e[32mpatched\e[39m"
          rescue => e
            counts[:failed] += 1
            output.puts "\e[31mFAILED\e[39m (#{e.message.lines.last.to_s.strip[0, 200]})"
            output.puts "    rollback if it switched: #{RVM} alias create default ruby-#{inventories[guest][:default]}; restore passenger_ruby in /etc/nginx/passenger.conf; systemctl reload nginx"
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
      echo "passenger_ruby=$(sed -n 's/^[[:space:]]*passenger_ruby[[:space:]]\\{1,\\}\\([^;]*\\);.*/\\1/p' /etc/nginx/passenger.conf 2>/dev/null | head -1)"
      echo "passenger_version=$($RVM default do passenger-config --version 2>/dev/null)"
      for f in $(find /var/www -maxdepth 4 -name Gemfile.lock -not -path '*/releases/*' -not -path '*/shared/*' -not -path '*/bundle/*' 2>/dev/null | sort); do
        echo "app=$(dirname $f)|$(awk '/^BUNDLED WITH/ { getline; gsub(/ /, ""); print }' $f)"
      done
      echo "units=$(systemctl list-units --plain --no-legend 'delayed_jobs@*.service' 'rake-*.service' monitoring.service 2>/dev/null | awk '{ print $1 }' | tr '\\n' ' ')"
      echo "os=$(. /etc/os-release; echo $ID-$VERSION_ID)"
      echo "arch=$(dpkg --print-architecture)"
    SH

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

    def archive_name os, arch
      "cloudmodel-#{ruby_name}-#{os}-#{arch}.tar.gz"
    end

    def remote_archive os, arch
      "/tmp/#{archive_name os, arch}"
    end

    def local_archive os, arch
      File.join @local_dir.to_s, archive_name(os, arch)
    end

    # Compiles the Ruby on the build host when needed and pulls the archive
    # onto the controller (once per os/arch; a cached archive from an earlier
    # run is reused and nothing is compiled).
    def ensure_archive os, arch
      local = local_archive os, arch
      if File.file? local
        output.puts "  archive cached: #{local}"
        return
      end

      host = CloudModel::Host.build_host(arch) or raise "no build host for arch #{arch} (CloudModel.config.build_host_name)"
      template = build_template(os, arch) or raise "no finished guest template with a ruby for #{os} #{arch}"
      output.puts "  compiling #{ruby_name} on #{host.name} in a clone of template #{template.id} (several minutes) …"
      CloudModel::Workers::RubyBuildWorker.new(host, template: template, version: version, rvm_update: @rvm_update).build! remote_archive(os, arch)
      FileUtils.mkdir_p @local_dir
      host.sftp.download! remote_archive(os, arch), local
      output.puts "  archive: #{local} (#{(File.size(local) / 1024.0**2).round} MB)"
    end

    def patch_guest guest, inv, os, arch
      host = guest.host
      unless installed? inv
        remote = remote_archive os, arch
        success, _ = host.exec "test -f #{remote.shellescape}"
        host.sftp.upload! local_archive(os, arch), remote unless success
        host.exec! "/usr/bin/lxc exec #{guest.current_lxd_container.name.shellescape} -- tar -C #{RVM_PATH} -xzf - < #{remote.shellescape}",
          "unpacking the ruby into #{guest.name} failed"
      end
      guest.exec! "bash -c #{switch_script(inv).shellescape}", "switching #{guest.name} to #{ruby_name} failed"
      after = inventory guest
      raise "guest still runs #{after[:default]} after the switch" unless up_to_date?(after)
    end

    # Everything that can fail runs before anything changes: bundler in the
    # locked versions, `bundle check` per application. Then the default alias,
    # passenger.conf and the reload, then the job units.
    def switch_script inv
      bundlers = inv[:apps].map { |a| a[:bundled_with] }.compact.uniq
      units = inv[:units]
      <<~SH
        set -e
        test -x #{ruby_bin}
        #{bundlers.map { |b| "#{RVM} #{ruby_name} do gem install bundler -v #{b.shellescape} --no-document >/dev/null" } * "\n"}
        #{inv[:apps].map { |a| "(cd #{a[:dir].shellescape} && #{RVM} #{ruby_name} do bundle check >/dev/null) || { echo \"bundle check failed in #{a[:dir]}\"; exit 3; }" } * "\n"}
        #{RVM} alias create default #{ruby_name}
        if [ -f /etc/nginx/passenger.conf ]; then
          sed -i 's#^\\([[:space:]]*passenger_ruby[[:space:]]\\{1,\\}\\)[^;]*;#\\1#{ruby_bin};#' /etc/nginx/passenger.conf
          nginx -t
          systemctl reload nginx
        fi
        #{units.map { |u| "systemctl try-restart #{u.shellescape}" } * "\n"}
      SH
    end
  end
end
