module CloudModel
  # Brings the guests on the mounted-release layout ({RubyRelease},
  # Workers::Mixins::RubyLayout) onto the newest patch release of their
  # lines — the Ruby counterpart of {MongodbPatch}, and what the apt
  # security origins do for the distribution packages:
  #
  # 1. the release index of ruby-lang.org names the newest release of every
  #    line any guest uses; a release nobody has yet is built on the build
  #    host and sent to every host with guests of that os/arch (this changes
  #    nothing a guest runs — the shims pick a release only when a program
  #    starts, and within a line the ABI is stable);
  # 2. per guest, `/usr/local/ruby/current` is pointed at the newest release
  #    of the default line, and the Passenger apps and the job units are
  #    restarted so the running processes move; the inventory afterwards
  #    (what the app user's processes really execute) decides whether the
  #    guest is patched. A guest whose default line is pinned to a release
  #    (`Guest#ruby_lines` with a patch level) is left alone, and gets an
  #    issue once it runs something older than the newest release of its
  #    line — the forgotten pin.
  #
  # Guests still on the RVM layout (no /opt/ruby) are skipped: {RubyPatch}
  # (`rake cloudmodel:guest:patch_ruby`) serves them until their redeploy.
  #
  # Driven by `rake cloudmodel:ruby:patch` (dry run unless CONFIRM=1) and,
  # when `CloudModel.config.ruby_unattended` is on, by the nightly
  # maintenance run (`cloudmodel:guest:backup_all`, after the MongoDB patch,
  # before the backups), inside `CloudModel.config.ruby_unattended_window`.
  class RubyReleasePatch
    attr_reader :output, :deadline, :index

    # What a guest on the mounted layout looks like: the default line, the
    # current symlink, the releases it sees, and which release the app
    # user's processes run (Passenger separately from the units' processes).
    INVENTORY_SCRIPT = <<~SH
      test -d /opt/ruby || { echo "layout=rvm"; exit 0; }
      echo "layout=mount"
      echo "default=$(cat /etc/ruby-version 2>/dev/null | tr -d '[:space:]')"
      echo "current=$(readlink /usr/local/ruby/current 2>/dev/null | sed 's#.*/ruby-##')"
      echo "installed=$(ls -1 /opt/ruby 2>/dev/null | sed -n 's/^ruby-//p' | tr '\\n' ' ')"
      rubies() { grep -o '/opt/ruby/ruby-[0-9.]*/' | sed 's#/opt/ruby/ruby-##; s#/##' | sort -u | tr '\\n' ' '; }
      pass=""; other=""
      for p in $(ps -u www -o pid= 2>/dev/null); do
        e=$(readlink /proc/$p/exe 2>/dev/null) || continue
        if ps -o args= -p $p 2>/dev/null | grep -q '^Passenger'; then pass="$pass $e"; else other="$other $e"; fi
      done
      echo "passenger_running=$(echo "$pass" | tr ' ' '\\n' | rubies)"
      echo "other_running=$(echo "$other" | tr ' ' '\\n' | rubies)"
      echo "apps=$(ls -d /var/www/*/current 2>/dev/null | tr '\\n' ' ')"
      echo "units=$(systemctl list-units --plain --no-legend 'delayed_jobs@*.service' 'rake-*.service' monitoring.service 2>/dev/null | awk '{ print $1 }' | tr '\\n' ' ')"
    SH

    # @param deadline [Time, nil] start no further guest after this
    # @param index [Hash, nil] the release index ({RubyRelease.index}),
    #   fetched when not given
    def initialize output: $stdout, deadline: nil, index: nil
      @output = output
      @deadline = deadline
      @index = index
    end

    # The guests on the mounted layout the run looks at: running guests
    # with a Ruby line.
    def self.guests_with_ruby guests
      guests.select { |g| %i(finished failed).include?(g.deploy_state) && g.ruby_lines_needed.any? }
    end

    def self.nightly! output: $stdout, now: Time.now
      unless CloudModel.config.ruby_unattended
        output.puts 'Ruby unattended patching is switched off (CloudModel.config.ruby_unattended).'
        return nil
      end
      from, till = CloudModel.config.ruby_unattended_window
      deadline = CloudModel::MongodbPatch.deadline_in_window now, from, till
      unless deadline
        output.puts "Ruby unattended patching starts between #{from} and #{till} UTC only; it is #{now.utc.strftime('%H:%M')} UTC — nothing is patched in this run."
        return nil
      end
      new(output: output, deadline: deadline).patch! guests_with_ruby(CloudModel::Guest.all), dry_run: false
    rescue Exception => e
      raise if e.is_a?(SignalException) || e.is_a?(SystemExit)
      CloudModel.log_exception e
      output.puts "\e[31mRuby patch run crashed\e[39m: #{e.class}: #{e.message[0, 200]}"
      nil
    end

    # @return [Hash] parsed inventory of a guest
    def inventory guest
      success, out = guest.exec "sh -c #{INVENTORY_SCRIPT.shellescape}"
      raise "inventory failed: #{out.to_s.lines.last.to_s.strip[0, 160]}" unless success
      inv = {}
      out.to_s.each_line do |line|
        key, value = line.chomp.split('=', 2)
        inv[key.to_sym] = value.to_s.strip if key
      end
      inv[:installed] = inv[:installed].to_s.split
      inv[:passenger_running] = inv[:passenger_running].to_s.split
      inv[:other_running] = inv[:other_running].to_s.split
      inv[:running] = (inv[:passenger_running] + inv[:other_running]).uniq
      inv[:apps] = inv[:apps].to_s.split
      inv[:units] = inv[:units].to_s.split
      inv
    end

    # @param guests [Array<CloudModel::Guest>]
    # @return [Hash] counts
    def patch! guests, dry_run: true
      counts = { patched: 0, current: 0, skipped: 0, failed: 0, deferred: 0, built: 0, synced: 0 }
      targets = release_targets guests
      output.puts "Lines in use: #{targets.map { |(os, arch, line), v| "#{line} (#{os} #{arch}) → #{v || 'no release in the index'}" }.join(', ').presence || 'none'}"

      # 1. the newest release of every line on the build host and every host
      targets.each do |(os, arch, line), version|
        next unless version
        release = CloudModel::RubyRelease.new version: version, os_version: os, arch: arch
        hosts = guests.select { |g| g.os_version == os && g.host.arch == arch }.map(&:host).uniq
        begin
          build_host = release.build_host
          unless release.present_on? build_host
            if dry_run
              output.puts "  would build #{release.name} for #{os} #{arch} on #{build_host.name} and sync it to #{hosts.map(&:name).join(', ')}"
              next
            end
            release.ensure_built! output: output
            counts[:built] += 1
          end
          hosts.each do |host|
            next if release.present_on? host
            if dry_run
              output.puts "  would sync #{release.name} #{build_host.name} → #{host.name}"
              next
            end
            release.ensure_on! host, output: output
            counts[:synced] += 1
          end
        rescue => e
          output.puts "  \e[31m#{release.name} for #{os} #{arch} FAILED\e[39m: #{e.message.lines.last.to_s.strip[0, 200]}"
          counts[:failed] += 1
        end
      end

      # 2. the guests
      guests.sort_by { |g| [g.host.name, g.name] }.each do |guest|
        if deadline && Time.now > deadline
          counts[:deferred] += 1
          next
        end
        patch_guest guest, counts, dry_run: dry_run
      end
      output.puts "  \e[33m#{counts[:deferred]} guest(s) deferred\e[39m: past #{deadline.utc.strftime('%H:%M')} UTC, left for the next night" if counts[:deferred] > 0
      counts
    end

    # The newest release in the index for every (os, arch, line) a guest uses.
    # @return [Hash{Array => String, nil}]
    def release_targets guests
      index = @index ||= CloudModel::RubyRelease.index
      guests.flat_map { |g| g.ruby_lines_needed.map { |l| [g.os_version, g.host.arch, CloudModel::RubyRelease.line_of(l)] } }.uniq.to_h do |key|
        [key, CloudModel::RubyRelease.newest(key[2], index.keys)]
      end
    end

    private

    def label guest
      "#{guest.name}@#{guest.host.name}"
    end

    def patch_guest guest, counts, dry_run:
      inv = inventory guest
      if inv[:layout] == 'rvm'
        counts[:skipped] += 1
        output.puts "  #{label guest}: \e[33mskipped\e[39m: RVM layout (patch_ruby serves it until its redeploy)"
        return
      end
      line = guest.ruby_default_line
      pinned = guest.ruby_lines.to_a.first.to_s =~ CloudModel::RubyRelease::VERSION ? guest.ruby_lines.first : nil
      newest = CloudModel::RubyRelease.newest line, inv[:installed]
      unless newest
        counts[:failed] += 1
        output.puts "  #{label guest}: \e[31mFAILED\e[39m: no release of line #{line} under /opt/ruby (has #{inv[:installed].join(' ').presence || 'none'})"
        open_issue guest, "No Ruby release of line #{line} under /opt/ruby (has #{inv[:installed].join(' ').presence || 'none'})"
        return
      end
      target = pinned && inv[:installed].include?(pinned) ? pinned : newest
      stale = inv[:running].reject { |v| v == target }
      if inv[:current] == target && stale.empty?
        counts[:current] += 1
        output.puts "  #{label guest}: on #{target}#{pinned ? ' (pinned)' : ''}"
        resolve_issue guest
        if pinned && newer?(newest, pinned)
          open_issue guest, "Pinned to Ruby #{pinned} while #{newest} is installed on the host — a forgotten pin?", key: :ruby_pinned_behind, severity: :info
        end
        return
      end
      if pinned && inv[:current] == target
        # pinned and on its pin; only the restart of stale processes is due
        output.puts "  #{label guest}: pinned to #{target}, still running #{stale.join(' ')}"
      else
        output.puts "  #{label guest}: #{inv[:current].presence || '?'} → #{target}#{stale.any? ? " (running #{stale.join(' ')})" : ''}"
      end
      if dry_run
        output.puts "    would point current at ruby-#{target} and restart #{inv[:apps].size} app(s), #{inv[:units].size} unit(s)"
        return
      end
      switch guest, inv, target
      after = nil
      36.times do
        sleep 5
        after = inventory guest
        break if after[:running].all? { |v| v == target }
      end
      left = after[:running].reject { |v| v == target }
      raise "still running #{left.join(' ')} after the switch" if left.any?
      counts[:patched] += 1
      resolve_issue guest
      output.puts "  #{label guest}: \e[32mpatched\e[39m to #{target}#{after[:running].empty? ? ' (no ruby process running yet)' : ''}"
    rescue => e
      counts[:failed] += 1
      output.puts "  #{label guest}: \e[31mFAILED\e[39m (#{e.message.lines.last.to_s.strip[0, 200]})"
      open_issue guest, "Ruby patch failed: #{e.message.lines.last.to_s.strip[0, 300]}"
    end

    # Points current at the release and restarts what runs an older one.
    def switch guest, inv, target
      steps = ['set -e', "test -x /opt/ruby/ruby-#{target}/bin/ruby"]
      steps << "ln -sfn /opt/ruby/ruby-#{target} /usr/local/ruby/current" unless inv[:current] == target
      if inv[:passenger_running].any? { |v| v != target } || inv[:current] != target
        steps += inv[:apps].map { |a| "/usr/bin/env PATH=/usr/local/ruby/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin passenger-config restart-app #{File.dirname(a).shellescape} --ignore-app-not-running >/dev/null 2>&1 || true" }
      end
      if inv[:other_running].any? { |v| v != target } || inv[:current] != target
        steps += inv[:units].map { |u| "systemctl --no-block try-restart #{u.shellescape}" }
      end
      guest.exec! "sh -c #{(steps.join("\n") + "\n").shellescape}", "switching #{guest.name} to ruby-#{target} failed"
    end

    def newer? a, b
      Gem::Version.new(a) > Gem::Version.new(b)
    end

    ISSUE_KEY = :ruby_patch

    def open_issue guest, message, key: ISSUE_KEY, severity: :warning
      issue = guest.item_issues.find_or_initialize_by key: key, resolved_at: nil
      issue.severity = severity
      issue.message = message
      issue.save
    rescue => e
      output.puts "  (could not record the issue: #{e.message[0, 120]})"
    end

    def resolve_issue guest
      guest.item_issues.where(key: ISSUE_KEY, resolved_at: nil).update_all resolved_at: Time.now
    rescue => e
      output.puts "  (could not resolve the issue: #{e.message[0, 120]})"
    end
  end
end
