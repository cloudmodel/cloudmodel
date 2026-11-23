module CloudModel
  # Brings the MongoDB packages of running guests onto the newest patch
  # release of their minor line (7.0.x, 8.0.x) — the way unattended-upgrades
  # does it for the distribution packages, but aware of the replica sets.
  #
  # The guests get their mongod from MongoDB's own repository, one apt source
  # per minor line (MongodbComponentWorker), so the apt candidate is always a
  # patch release of the line the service names; a change of the line stays a
  # redeploy with a feature compatibility version step. The repository is
  # deliberately not among the unattended-upgrades origins: the package's
  # postinst restarts mongod on every upgrade, and apt on every member in the
  # same hour would take two members of a set down at once, or restart a
  # primary without a step-down. So the upgrade is orchestrated from here:
  #
  # * per replica set the arbiters first, then the secondaries one by one,
  #   the primary last — after `replSetStepDown`, so the set elects another
  #   member instead of losing writes for the length of the restart;
  # * before every member the set has to be healthy: every member up, one
  #   primary, the lag under the limit, and a majority of the voting members
  #   left when this one goes down — otherwise the set is skipped with an
  #   issue, nothing is touched;
  # * after every member the run waits until the member is back as
  #   SECONDARY (or ARBITER) on the new release and has caught up, before the
  #   next one is taken down;
  # * standalone services are upgraded and restarted directly (the only
  #   outage this run causes, seconds long).
  #
  # Driven by `rake cloudmodel:mongodb:patch` (dry run unless CONFIRM=1) and,
  # when `CloudModel.config.mongodb_unattended` is on, by the nightly
  # maintenance run (`cloudmodel:guest:backup_all`, before the backups, under
  # the same lock), so a security release reaches the fleet the night after
  # it is published.
  class MongodbPatch
    attr_reader :output, :lag_limit, :member_timeout

    # Refreshes the package list of the MongoDB repository alone (the nightly
    # apt-daily run refreshes the rest), then reports what is installed, what
    # apt would install and which packages of the family are there.
    INVENTORY_SCRIPT = <<~SH
      list=$(ls /etc/apt/sources.list.d/mongodb-org-*.list 2>/dev/null | head -1)
      if [ -n "$list" ]; then
        apt-get update -qq -o Dir::Etc::sourcelist="$list" -o Dir::Etc::sourceparts=- -o APT::Get::List-Cleanup=0 >/dev/null 2>&1 || echo "update_failed=1"
      fi
      echo "installed=$(dpkg-query -W -f='${Version}' mongodb-org-server 2>/dev/null)"
      echo "candidate=$(apt-cache policy mongodb-org-server 2>/dev/null | awk '/Candidate:/ { print $2 }')"
      echo "packages=$(dpkg-query -W -f='${Package} ' 'mongodb-org*' 2>/dev/null)"
    SH

    # The package's postinst restarts mongod; confold keeps the rendered
    # mongod.conf, the lock timeout rides out a running apt-daily job.
    UPGRADE = "DEBIAN_FRONTEND=noninteractive apt-get install -y -q --only-upgrade -o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confold".freeze

    DATA_STATES = %w(PRIMARY SECONDARY).freeze
    DONE_STATES = %w(SECONDARY ARBITER).freeze

    # @param lag_limit [Integer] seconds of replication lag a set may have
    #   before and after each member
    # @param member_timeout [Integer] seconds to wait for a member to come
    #   back on the new release and catch up
    def initialize output: $stdout, lag_limit: 30, member_timeout: 900
      @output = output
      @lag_limit = lag_limit.to_i
      @member_timeout = member_timeout.to_i
    end

    # The MongoDB services of running guests. A guest whose last redeploy
    # failed keeps its previous container running and is part of its set, so
    # it is in; a guest being deployed right now is not.
    # @return [Array<CloudModel::Services::Mongodb>]
    def self.services_of guests
      guests.select { |g| %i(finished failed).include? g.deploy_state }.flat_map do |guest|
        guest.services.select { |s| s.is_a?(CloudModel::Services::Mongodb) }
      end
    end

    # Runs the unattended patch of the whole fleet; never raises — the
    # nightly run must go on to the backups whatever happens here.
    # @return [Hash, nil] the counts, nil when switched off or crashed
    def self.nightly! output: $stdout
      unless CloudModel.config.mongodb_unattended
        output.puts 'MongoDB unattended patching is switched off (CloudModel.config.mongodb_unattended).'
        return nil
      end
      new(output: output).patch! services_of(CloudModel::Guest.all), dry_run: false
    rescue Exception => e
      raise if e.is_a?(SignalException) || e.is_a?(SystemExit)
      CloudModel.log_exception e
      output.puts "\e[31mMongoDB patch run crashed\e[39m: #{e.class}: #{e.message[0, 200]}"
      nil
    end

    # @return [Hash] installed, candidate, packages and the running version
    def inventory service
      success, out = service.guest.exec "sh -c #{INVENTORY_SCRIPT.shellescape}"
      raise "inventory failed: #{out.to_s.lines.last.to_s.strip[0, 160]}" unless success
      inv = {}
      out.to_s.each_line do |line|
        key, value = line.chomp.split('=', 2)
        inv[key.to_sym] = value.to_s.strip if key
      end
      raise 'no mongodb-org-server package installed' if inv[:installed].blank?
      inv[:candidate] = nil if inv[:candidate].blank? || inv[:candidate] == '(none)'
      inv[:packages] = inv[:packages].to_s.split
      inv[:update_failed] = inv[:update_failed] == '1'
      inv[:running] = running_version(service)
      inv
    end

    # Whether apt has a newer package than the one installed, or the running
    # mongod is still an older one than the package (a restart that never
    # happened).
    def behind? inv
      return false unless inv[:candidate]
      newer?(inv[:candidate], inv[:installed]) || (inv[:running] && newer?(inv[:installed], inv[:running]))
    end

    # @param services [Array<CloudModel::Services::Mongodb>]
    # @return [Hash] counts of :patched, :current, :skipped, :failed members
    def patch! services, dry_run: true
      counts = { patched: 0, current: 0, skipped: 0, failed: 0 }
      sets, standalone = services.partition(&:mongodb_replication_set)
      groups = sets.group_by(&:mongodb_replication_set).sort_by { |set, _| [own_set?(set) ? 1 : 0, set.name.to_s] }

      groups.each do |set, members|
        output.puts "\n== replica set #{set.name}: #{members.size} member(s)#{own_set?(set) ? ' (this admin\'s own database, last)' : ''}"
        patch_set set, members, counts, dry_run: dry_run
      end

      if standalone.any?
        output.puts "\n== standalone: #{standalone.size} service(s)"
        standalone.sort_by { |s| [own_member?(s) ? 1 : 0, label(s)] }.each do |service|
          patch_standalone service, counts, dry_run: dry_run
        end
      end
      counts
    end

    private

    def label service
      "#{service.guest.name}@#{service.guest.host.name}"
    end

    def newer? a, b
      return false if a.blank? || b.blank?
      if a =~ /\A[\d.]+\z/ && b =~ /\A[\d.]+\z/
        Gem::Version.new(a) > Gem::Version.new(b)
      else
        a != b
      end
    end

    # The replica set this admin application itself reads from: its members
    # are patched last, so a failover in the middle of the run hits nothing
    # but the last steps.
    def own_set? set
      (set.service_uris & own_addresses).any?
    rescue
      false
    end

    def own_member? service
      own_addresses.include? service.server_uri
    end

    def own_addresses
      @own_addresses ||= Mongoid.default_client.cluster.addresses.map(&:to_s)
    rescue
      @own_addresses = []
    end

    # What mongod itself says about the member: the set it belongs to (nil
    # for a standalone), whether it is the primary, and whether it is a
    # working member (primary or secondary) right now.
    def member_role service
      hello = direct_command service, hello: 1
      primary = hello['isWritablePrimary'] || hello['ismaster'] || false
      { set: hello['setName'], primary: primary, member: primary || hello['secondary'] == true }
    rescue Mongo::Error, Timeout::Error, SocketError, Errno::ECONNREFUSED
      { set: nil, primary: false, member: false }
    end

    def step_down_member service
      output.puts "  #{label service}: primary, stepping down"
      attempts = 0
      begin
        attempts += 1
        direct_command service, replSetStepDown: 60, secondaryCatchUpPeriodSecs: 15
      rescue Mongo::Error::OperationFailure => e
        raise "step-down refused: #{e.message[0, 160]}" if attempts >= 3
        sleep 10
        retry
      rescue Mongo::Error::SocketError, Mongo::Error::ConnectionPerished, Mongo::Error::NoServerAvailable
        # the server closes the connection when it steps down
      end
      wait_until(90, "#{label service} is still the primary after the step-down") { !member_role(service)[:primary] }
    end

    def patch_set set, members, counts, dry_run:
      missing = set.services.to_a.reject { |s| members.any? { |m| m.id == s.id } }
      if missing.any?
        counts[:skipped] += members.size
        names = missing.map { |s| "#{s.guest&.name || s.server_uri} (#{s.guest&.deploy_state || 'no guest'})" } * ', '
        output.puts "  \e[33mskipped\e[39m: #{missing.size} member(s) of the set are not in this run: #{names} — a set is patched as a whole"
        open_set_issue set, "Member(s) not in the patch run: #{names}. The set was not patched."
        return
      end
      inventories = {}
      members.each do |service|
        begin
          inventories[service] = inventory service
        rescue => e
          counts[:failed] += 1
          output.puts "  #{label service}: \e[31mFAILED\e[39m (#{e.message[0, 160]})"
        end
      end
      todo = inventories.select { |_s, inv| behind? inv }.keys
      inventories.each do |service, inv|
        state = todo.include?(service) ? "#{inv[:running] || inv[:installed]} → #{inv[:candidate]}" : "on #{inv[:installed]}"
        state << ' (apt update failed, from the existing lists)' if inv[:update_failed]
        output.puts "  #{label service}: #{state}"
      end
      counts[:current] += inventories.size - todo.size
      return if todo.empty?

      unless inventories.size == members.size
        counts[:skipped] += todo.size
        output.puts "  \e[33mskipped\e[39m: not every member answered — a set is only patched when all of it is known"
        open_set_issue set, 'A member did not answer the inventory; the set was not patched.'
        return
      end

      status = set_status set
      if (reason = blocked_reason(set, status))
        counts[:skipped] += todo.size
        output.puts "  \e[33mskipped\e[39m: #{reason}"
        open_set_issue set, "#{reason} — the set was not patched."
        return
      end

      order = ordered(todo, status)
      if dry_run
        output.puts "  would patch #{order.map { |s| "#{label s} (#{role_of s, status})" }.join(', ')}, one after the other, the primary after a step-down"
        return
      end

      order.each do |service|
        status = set_status set
        if (reason = blocked_reason(set, status, leaving: service))
          counts[:skipped] += 1
          output.puts "  #{label service}: \e[33mskipped\e[39m: #{reason}"
          open_set_issue set, "#{reason} — #{service.guest.name} was not patched."
          next
        end
        begin
          step_down service, set if role_of(service, status) == 'PRIMARY'
          upgrade service, inventories[service]
          wait_for_member set, service, inventories[service][:candidate]
          counts[:patched] += 1
          resolve_issue service.guest
          output.puts "  #{label service}: \e[32mpatched\e[39m to #{inventories[service][:candidate]}"
        rescue => e
          counts[:failed] += 1
          output.puts "  #{label service}: \e[31mFAILED\e[39m (#{e.message.lines.last.to_s.strip[0, 200]})"
          open_guest_issue service.guest, "MongoDB patch to #{inventories[service][:candidate]} failed: #{e.message.lines.last.to_s.strip[0, 300]}"
          output.puts "  \e[33mstopping with this set\e[39m: the remaining members stay as they are until it is healthy again"
          break
        end
      end
      resolve_set_issue set if counts[:failed].zero?
    end

    # A service without a replica set in the admin's data may still be a
    # member of one (the admin's own database is such a case): mongod says
    # so in `hello`. Such a member steps down when it is the primary and has
    # to come back as a member, the rest of the set is not known here.
    def patch_standalone service, counts, dry_run:
      inv = inventory service
      role = member_role service
      unless behind? inv
        counts[:current] += 1
        output.puts "  #{label service}: on #{inv[:installed]}"
        return
      end
      note = role[:set] ? " (member of the unmanaged replica set #{role[:set]}, #{role[:primary] ? 'primary — steps down first' : 'secondary'})" : ' (standalone — restarts)'
      output.puts "  #{label service}: #{inv[:running] || inv[:installed]} → #{inv[:candidate]}#{note}#{dry_run ? ', would upgrade' : ''}"
      return if dry_run
      step_down_member service if role[:set] && role[:primary]
      upgrade service, inv
      wait_until(member_timeout, "mongod on #{label service} did not come back on #{inv[:candidate]}") do
        running_version(service) == inv[:candidate] && (role[:set].nil? || member_role(service)[:member])
      end
      counts[:patched] += 1
      resolve_issue service.guest
      output.puts "  #{label service}: \e[32mpatched\e[39m to #{inv[:candidate]}"
    rescue => e
      counts[:failed] += 1
      output.puts "  #{label service}: \e[31mFAILED\e[39m (#{e.message.lines.last.to_s.strip[0, 200]})"
      open_guest_issue service.guest, "MongoDB patch failed: #{e.message.lines.last.to_s.strip[0, 300]}"
    end

    # replSetGetStatus with the services mapped in, plus the voting members
    # from the set configuration.
    def set_status set
      status = set.status
      config = set.read_config
      votes = Hash[(config['members'] || []).map { |m| [m['host'], m['votes'].to_i] }]
      status['members'].each { |m| m['votes'] = votes.fetch(m['name'], 1) }
      status
    rescue => e
      { 'ok' => 0, 'members' => [], 'error' => "#{e.class}: #{e.message.lines.first.to_s.strip[0, 160]}" }
    end

    # Why the set must not be touched right now, or nil.
    # @param leaving [Services::Mongodb, nil] the member about to go down
    def blocked_reason set, status, leaving: nil
      members = status['members']
      return "replica set status unavailable (#{status['error'] || 'replSetGetStatus not ok'})" unless status['ok'] == 1.0 || status['ok'] == 1
      unknown = members.select { |m| !m['found'] }
      return "member(s) not in the set: #{unknown.map { |m| m['name'] } * ', '}" if unknown.any?
      down = members.reject { |m| m['health'].to_f == 1.0 }
      return "member(s) down: #{down.map { |m| m['name'] } * ', '}" if down.any?
      primaries = members.select { |m| m['stateStr'] == 'PRIMARY' }
      return 'no primary' if primaries.empty?
      return 'more than one primary' if primaries.size > 1
      odd = members.reject { |m| (DATA_STATES + %w(ARBITER)).include? m['stateStr'] }
      return "member(s) in state #{odd.map { |m| "#{m['name']} #{m['stateStr']}" } * ', '}" if odd.any?
      lag = max_lag members
      return "replication lag #{lag.round}s is over the limit of #{lag_limit}s" if lag > lag_limit
      if leaving
        voting = members.select { |m| m['votes'] > 0 }
        left = voting.reject { |m| m['name'] == leaving.server_uri }
        if left.size < voting.size / 2 + 1
          return "taking #{leaving.guest.name} down leaves #{left.size} of #{voting.size} voting members, no majority"
        end
      end
      nil
    end

    def max_lag members
      primary = members.find { |m| m['stateStr'] == 'PRIMARY' && m['optimeDate'] }
      return 0.0 unless primary
      members.select { |m| m['stateStr'] == 'SECONDARY' && m['optimeDate'] }.map { |m| (primary['optimeDate'] - m['optimeDate']).to_f }.max.to_f.clamp(0.0, Float::INFINITY)
    end

    def role_of service, status
      member = status['members'].find { |m| m['name'] == service.server_uri }
      member ? member['stateStr'] : 'N/C'
    end

    # Arbiters first (nothing to catch up), then the secondaries, the one
    # with the lowest priority first, the primary last.
    def ordered services, status
      services.sort_by do |s|
        case role_of(s, status)
        when 'ARBITER' then [0, s.guest.name]
        when 'SECONDARY' then [1, s.mongodb_replication_priority.to_i, s.guest.name]
        else [2, s.guest.name]
        end
      end
    end

    # Asks the primary to step down for 60 seconds (the time the upgrade and
    # restart take) and waits for another member to take over. The step-down
    # refuses while no secondary has caught up; a few retries ride that out.
    def step_down service, set
      step_down_member service
      wait_until(90, "no new primary elected in #{set.name} after the step-down") do
        members = set.status['members']
        members.any? { |m| m['stateStr'] == 'PRIMARY' && m['name'] != service.server_uri }
      end
    end

    def upgrade service, inv
      packages = inv[:packages].any? ? inv[:packages] : %w(mongodb-org-server)
      output.puts "  #{label service}: upgrading #{packages.size} package(s) to #{inv[:candidate]} (mongod restarts)"
      service.guest.exec! "sh -c #{"#{UPGRADE} #{packages.map(&:shellescape) * ' '}".shellescape}", 'apt-get install failed'
      # The postinst restarts mongod; where it did not (a masked unit, a
      # policy-rc.d), restart it here.
      restarted = false
      wait_until(120, "mongod on #{label service} not reachable after the upgrade") do
        version = running_version service
        if version && version != inv[:candidate] && !restarted
          output.puts "  #{label service}: still running #{version}, restarting mongod"
          service.guest.exec! '/bin/systemctl restart mongod', 'failed to restart mongod'
          restarted = true
          false
        else
          !version.nil?
        end
      end
    end

    # Waits until the member runs the release, is SECONDARY or ARBITER again
    # and has caught up with the primary.
    def wait_for_member set, service, version
      wait_until(member_timeout, "#{label service} did not come back as a caught-up member on #{version}") do
        running = running_version service
        next false unless running == version
        members = set.status['members']
        member = members.find { |m| m['name'] == service.server_uri }
        next false unless member && member['health'].to_f == 1.0 && DONE_STATES.include?(member['stateStr'])
        member['stateStr'] == 'ARBITER' || max_lag(members) <= lag_limit
      end
    end

    def wait_until seconds, message, interval: 5
      deadline = Time.now + seconds
      loop do
        return true if yield
        raise message if Time.now > deadline
        sleep interval
      end
    end

    # The version the mongod on this member really runs, nil while it is down.
    def running_version service
      direct_command(service, buildInfo: 1)['version']
    rescue Mongo::Error, Timeout::Error, SocketError, Errno::ECONNREFUSED
      nil
    end

    def direct_command service, command
      client = Mongo::Client.new([service.server_uri], direct_connection: true, connect_timeout: 5,
        server_selection_timeout: 5, socket_timeout: 30, database: 'admin')
      client.database.command(command).first
    ensure
      client&.close
    end

    ISSUE_KEY = :mongodb_patch
    SET_ISSUE_KEY = :mongodb_patch_blocked

    def open_guest_issue guest, message
      issue = guest.item_issues.find_or_initialize_by key: ISSUE_KEY, resolved_at: nil
      issue.severity = :warning
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

    def open_set_issue set, message
      return unless set.respond_to?(:item_issues)
      issue = set.item_issues.find_or_initialize_by key: SET_ISSUE_KEY, resolved_at: nil
      issue.severity = :warning
      issue.message = message
      issue.save
    rescue => e
      output.puts "  (could not record the issue: #{e.message[0, 120]})"
    end

    def resolve_set_issue set
      return unless set.respond_to?(:item_issues)
      set.item_issues.where(key: SET_ISSUE_KEY, resolved_at: nil).update_all resolved_at: Time.now
    rescue => e
      output.puts "  (could not resolve the issue: #{e.message[0, 120]})"
    end
  end
end
