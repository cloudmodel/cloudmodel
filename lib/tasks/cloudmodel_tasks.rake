# Concurrent backup runs (nightly cron + a manual run) write into the same
# target datasets and dump dirs and quiesce the same services — they corrupt
# each other's chains. flock on a file in the shared data dir keeps it to one
# run per machine; a second start aborts immediately instead of interleaving.
def with_backup_run_lock
  lock = File.open CloudModel::BackupRun.lock_file_path, File::CREAT, 0o644
  unless lock.flock(File::LOCK_EX | File::LOCK_NB)
    abort "Another backup run is already active (#{lock.path} is locked) — refusing to start a second one."
  end
  yield
ensure
  if lock
    lock.flock File::LOCK_UN
    lock.close
  end
end

# Track the run in a BackupRun document (live log + progress for the admin
# UI). Failures — including Ctrl-C — mark the run failed and re-raise.
def with_tracked_backup_run total_subjects
  run = CloudModel::BackupRun.start! total_subjects: total_subjects
  CloudModel.current_backup_run = run
  begin
    yield
    run.finish! success: true
  rescue Exception => e
    run.append_log "Backup run aborted: #{e.class}: #{e.message}\n"
    run.finish! success: false
    raise
  ensure
    CloudModel.current_backup_run = nil
  end
end

namespace :cloudmodel do
  desc "Backup marked services and volumes, then clean up obsolete backups. " \
       "One switch per category: GUESTS / MONGO_SETS — unset = all, 0 = skip, name[,name] = only those " \
       "(naming only one category skips the other, e.g. GUESTS=hub06). " \
       "CLEANUP=0|1 forces the trailing cleanup off/on (default: on, except for name-filtered runs)."
  task :backup => [:environment] do
    # nil = all subjects, :off = skip category, Array = only these names
    parse = ->(value) do
      case value
      when nil, '' then nil
      when '0', 'none' then :off
      else value.split(',')
      end
    end
    guests_param = parse.call ENV['GUESTS']
    sets_param = parse.call ENV['MONGO_SETS']

    # Naming subjects in only one category implies skipping the other.
    sets_param ||= :off if guests_param.is_a? Array
    guests_param ||= :off if sets_param.is_a? Array

    cleanup = if ENV['CLEANUP']
      ENV['CLEANUP'] == '1'
    else
      !(guests_param.is_a?(Array) || sets_param.is_a?(Array))
    end

    with_backup_run_lock do
      guests = nil
      unless guests_param == :off
        guests = CloudModel::Guest.all
        if guests_param
          guests = guests.where :name.in => guests_param
          abort "No guest named #{guests_param * ', '} found." if guests.count == 0
        end
      end

      sets = nil
      unless sets_param == :off
        sets = CloudModel::MongodbReplicationSet.where has_backups: true
        if sets_param
          sets = sets.where :name.in => sets_param
          abort "No replica set with backups named #{sets_param * ', '} found." if sets.count == 0
        end
      end

      with_tracked_backup_run guests.try(:count).to_i + sets.try(:count).to_i do
        CloudModel::Guest.backup_all guests if guests
        CloudModel::MongodbReplicationSet.backup_all sets if sets
        CloudModel::BackupCleanup.run_after_backup if cleanup
      end
    end
  end

  namespace :migrate do
    desc "Move per-member MongoDB backup flags onto their replica set"
    task :mongodb_replset_backups => [:environment] do
      CloudModel::MongodbReplicationSet.all.each do |rs|
        # Read the raw stored flag (the getter now delegates to the set).
        members = rs.services.select { |service| service[:has_backups] }
        next if members.empty?

        rs.update_attribute :has_backups, true
        members.each do |service|
          service[:has_backups] = false # bypass the setter (would touch the set)
          service.save validate: false
          puts "Moved backup flag of #{service.name} to replica set #{rs.name}"
        end
      end
    end

    desc "One-time migration of tarball-built templates into ZFS build volumes on the build host — required for templates that can no longer be rebuilt. Dry run unless CONFIRM=1; HOST_ID overrides the configured build host."
    task :templates_to_zfs => [:environment] do
      host = if ENV['HOST_ID'].present?
        CloudModel::Host.find ENV['HOST_ID']
      else
        CloudModel::Host.build_host
      end
      abort "No build host configured — set config.build_host_name or pass HOST_ID=<id>" unless host

      CloudModel::ZfsTemplateMigration.new(host).migrate! dry_run: ENV['CONFIRM'] != '1'
    end
  end

  namespace :zfs do
    desc "Report the state of the move to ZFS-volume deploys: guests still on the legacy image layout (need one full redeploy before web image rollouts), template volumes missing on hosts, web images without artifacts. Read-only. PROBE=0 skips host access; HOST_ID=<id> limits to one host."
    task :status => [:environment] do
      hosts = if ENV['HOST_ID'].present?
        [CloudModel::Host.find(ENV['HOST_ID'])]
      else
        CloudModel::Host.all.to_a.sort_by(&:name)
      end
      abort "No hosts found in #{Rails.env} database — forgot RAILS_ENV=production?" if hosts.empty?

      CloudModel::ZfsRolloutStatus.new(hosts: hosts, probe: ENV['PROBE'] != '0').report
    end
  end

  namespace :mongodb do
    desc "Resize MongoDB guests in place: memory limit raised live, mongod.conf rewritten, WiredTiger cache set at runtime (no restart; RESTART=1 restarts — primary steps down first — only where mongod refuses). PLAN=<json> [{guest, host, memory_gb, cache_gb?}] or GUEST=<name> HOST=<name> MEMORY_GB=<n>. Shrinking needs SHRINK=1. Dry run unless CONFIRM=1."
    task :resize => [:environment] do
      confirm = ENV['CONFIRM'] == '1'
      restart = ENV['RESTART'] == '1'
      shrink = ENV['SHRINK'] == '1'
      puts "\e[33mDRY RUN — set CONFIRM=1 to apply.\e[39m" unless confirm

      plan = if ENV['PLAN'].present?
        JSON.parse(File.read(ENV['PLAN']))
      elsif ENV['GUEST'].present? and ENV['MEMORY_GB'].present?
        [{ 'guest' => ENV['GUEST'], 'host' => ENV['HOST'], 'memory_gb' => ENV['MEMORY_GB'].to_f }]
      else
        abort "Give PLAN=<json> or GUEST=<name> MEMORY_GB=<n> [HOST=<name>]"
      end

      entries = plan.filter_map do |row|
        guests = CloudModel::Guest.where(name: row['guest']).to_a
        guests.select! { |g| g.host.name == row['host'] } if row['host'].present?
        if guests.size != 1
          puts "#{row['guest']}#{row['host'] ? "@#{row['host']}" : ''}: \e[31mskipped — #{guests.size} matching guests\e[39m"
          next
        end
        service = guests.first.services.detect { |s| s.is_a?(CloudModel::Services::Mongodb) }
        next puts("#{row['guest']}: \e[31mskipped — no MongoDB service\e[39m") unless service
        [guests.first, service, row]
      end

      # Per replica set the secondaries first, the primary last.
      entries.sort_by! do |guest, service, _row|
        primary = (service.running_primary? rescue false)
        [service.mongodb_replication_set_id.to_s, primary ? 1 : 0, guest.name]
      end

      entries.each do |guest, service, row|
        target = (row['memory_gb'].to_f * 1024**3).to_i
        current = guest.memory_size.to_i
        label = "#{guest.name}@#{guest.host.name}"
        if target < current and not shrink
          puts "#{label}: #{current / 1024**3} GB → #{row['memory_gb']} GB would shrink a live container — skipped (SHRINK=1)"
          next
        end
        service.wiredtiger_cache_size_gb = row['cache_gb'].to_f if row['cache_gb']
        guest.memory_size = target
        cache = service.effective_wiredtiger_cache_size_gb
        running = (service.running_wiredtiger_cache_size_gb rescue '?')
        puts "#{label}: memory #{current / 1024**3} → #{row['memory_gb']} GB, cache #{running} → #{cache} GB"
        next unless confirm

        begin
          guest.save!      # raises limits.memory on the running container (Guest#apply_current_lxd_container_config)
          worker = CloudModel::Workers::Services::MongodbWorker.new guest.current_lxd_container, service
          how = worker.apply_wiredtiger_cache_live! restart: restart
          puts "  \e[32m#{how}\e[39m: cache now #{service.running_wiredtiger_cache_size_gb} GB, limit #{guest.current_lxd_container.lxc("config get #{guest.current_lxd_container.name} limits.memory")[1].to_s.strip}"
        rescue => e
          puts "  \e[31mFAILED: #{e.message.lines.first.to_s.strip}\e[39m"
        end
      end
    end
  end

  namespace :mongodb do
    desc "Patch the MongoDB packages of the running guests to the newest release of their line, replica-set-aware: arbiters, then secondaries one by one, the primary after a step-down; a set that is not healthy or without a backup younger than 36 h is skipped. SET=<name>, GUEST=<name>, HOST=<name> limit the scope; LAG=<s> (30) and TIMEOUT=<s> (900) the waits; UNTIL=HH:MM (UTC, the next such time) starts no further set after it; NO_BACKUP_CHECK=1 patches without the backup rule. Dry run unless CONFIRM=1."
    task :patch => [:environment] do
      confirm = ENV['CONFIRM'] == '1'
      puts "\e[33mDRY RUN — set CONFIRM=1 to apply.\e[39m" unless confirm

      guests = CloudModel::Guest.all.to_a
      abort "No guests in the #{Rails.env} database — forgot RAILS_ENV=production?" if guests.empty?
      guests.select! { |g| g.name == ENV['GUEST'] } if ENV['GUEST'].present?
      guests.select! { |g| g.host.name == ENV['HOST'] } if ENV['HOST'].present?
      services = CloudModel::MongodbPatch.services_of guests
      services.select! { |s| s.mongodb_replication_set&.name == ENV['SET'] } if ENV['SET'].present?
      if services.empty?
        filters = %w(SET GUEST HOST).select { |k| ENV[k].present? }.map { |k| "#{k}=#{ENV[k]}" }
        abort filters.any? ? "No running MongoDB service matches #{filters * ' '}" : "No MongoDB services on running guests in the #{Rails.env} database"
      end
      # A replica set is patched as a whole: a GUEST= or HOST= selection pulls
      # in the other members of the sets it touches.
      whole = services.filter_map(&:mongodb_replication_set).uniq.flat_map { |set| CloudModel::MongodbPatch.services_of set.guests }
      added = whole.reject { |s| services.any? { |given| given.id == s.id } }
      puts "Including the other members of the selected replica sets: #{added.map { |s| s.guest.name }.sort.join(', ')}" if added.any?
      services = (services + added).uniq(&:id)

      deadline = ENV['UNTIL'].present? ? CloudModel::MongodbPatch.next_time(ENV['UNTIL']) : nil
      patch = CloudModel::MongodbPatch.new lag_limit: ENV.fetch('LAG', 30), member_timeout: ENV.fetch('TIMEOUT', 900), deadline: deadline, require_backup: ENV['NO_BACKUP_CHECK'] != '1'
      counts = patch.patch! services, dry_run: !confirm
      puts "\n#{counts[:current]} member(s) current, #{counts[:patched]} patched, #{counts[:skipped]} skipped, #{counts[:deferred]} deferred, #{counts[:failed]} failed#{confirm ? '' : ' (dry run, nothing changed)'}."
      abort "#{counts[:failed]} member(s) failed" if counts[:failed] > 0
    end
  end

  namespace :cleanup do
    desc "Remove obsolete template tarballs (admin data dir + all hosts) and stale /cloud/build dirs. Dry run unless CONFIRM=1; keeps the newest KEEP (default 2) finished templates per type/arch plus everything referenced by deployed containers."
    task :templates => [:environment] do
      cleanup = CloudModel::TemplateCleanup.new keep_per_type: ENV.fetch('KEEP', 2)
      dry_run = ENV['CONFIRM'] != '1'

      puts "Keeping newest #{cleanup.keep_per_type} finished template(s) per type/arch + all container-referenced ones."
      cleanup.cleanup! dry_run: dry_run
      puts dry_run ? "\nDry run — nothing deleted. Re-run with CONFIRM=1 to delete." : "\nDone."
    end

    desc "Remove the stopped old containers of guests, keeping the newest KEEP (default 3, the running one always among them). Dry run unless CONFIRM=1; HOST_ID=<id> or GUEST=<name> limit the scope."
    task :containers => [:environment] do
      guests = if ENV['GUEST'].present?
        CloudModel::Guest.where(name: ENV['GUEST']).to_a
      elsif ENV['HOST_ID'].present?
        CloudModel::Host.find(ENV['HOST_ID']).guests.to_a
      else
        CloudModel::Guest.all.to_a
      end
      abort "No guests found in #{Rails.env} database — forgot RAILS_ENV=production?" if guests.empty?

      dry_run = ENV['CONFIRM'] != '1'
      puts "\e[33mDRY RUN — set CONFIRM=1 to actually remove.\e[39m" if dry_run
      CloudModel::ContainerCleanup.new(keep: ENV.fetch('KEEP', 3)).cleanup! guests.sort_by(&:name), dry_run: dry_run
    end

    desc "Remove dump backups of deleted guests/services/replica sets, apply retention to disabled/failing subjects, drop dangling latest links and empty dirs. Dry run unless CONFIRM=1."
    task :backups => [:environment] do
      dry_run = ENV['CONFIRM'] != '1'
      CloudModel::BackupCleanup.new.cleanup! dry_run: dry_run
      puts dry_run ? "\nDry run — nothing deleted. Re-run with CONFIRM=1 to delete." : "\nDone."
    end
  end

  namespace :host do
    task :load_host do
      @host_worker = CloudModel::Workers::HostWorker.new CloudModel::Host.find(ENV['HOST_ID'])
    end

    # desc "Deploy host"
    # task :deploy => [:environment, :load_host] do
    #   @host_worker.deploy
    # end
    #
    # desc "Redeploy host"
    # task :redeploy => [:environment, :load_host] do
    #   @host_worker.redeploy
    # end

    desc "Update tinc host files on one host (HOST_ID=<id>): write a file per VPN client and host, move files of deleted nodes aside, reload tincd"
    task :update_tinc_host_files => [:environment, :load_host] do
      removed = @host_worker.update_tinc_host_files
      puts "#{@host_worker.host.name}: tinc host files updated#{"; moved aside: #{removed * ', '}" unless removed.empty?}"
    end

    desc "Sync tinc host files on all deployed hosts. DRY_RUN=1 only lists files of nodes that no longer exist (deleted VPN clients or hosts)."
    task :sync_tinc_host_files => [:environment] do
      CloudModel::Host.tinc_peers_of(nil).each do |host|
        worker = CloudModel::Workers::HostWorker.new(host)
        begin
          if ENV['DRY_RUN'] == '1'
            stale = worker.stale_tinc_host_files
            puts "#{host.name}: #{stale.empty? ? 'no stale host files' : "would move aside #{stale * ', '}"}"
          else
            removed = worker.update_tinc_host_files
            puts "#{host.name}: updated#{"; moved aside #{removed * ', '}" unless removed.empty?}"
          end
        rescue => e
          puts "#{host.name}: FAILED (#{e.class}: #{e.message})"
        end
      end
    end

    desc "Push the tinc host files and tinc-up to a live host and set the tinc interface MTU in place. HOST_ID=<id> required; DRY_RUN=1 shows the changes; RESTART=1 restarts tincd (traffic between hosts drops for a few seconds) so it takes the fixed PMTU and MSS clamping."
    task :deploy_tinc_config => [:environment, :load_host] do
      host = @host_worker.host
      if ENV['DRY_RUN'] == '1'
        changes = @host_worker.tinc_config_changes
        puts "#{host.name}: #{changes.empty? ? 'tinc files up to date' : "#{changes.size} file(s) would change"}"
        changes.each do |path, (live, rendered)|
          puts "--- #{path}"
          (live.lines - rendered.lines).each { |line| puts "  - #{line}" }
          (rendered.lines - live.lines).each { |line| puts "  + #{line}" }
        end
        _, mtu = host.exec "cat /sys/class/net/vpn/mtu"
        puts "vpn MTU now #{mtu.strip}, would be #{CloudModel.config.tinc_mtu}"
      else
        @host_worker.deploy_tinc_config restart: ENV['RESTART'] == '1'
        puts "#{host.name}: tinc config deployed, vpn MTU #{CloudModel.config.tinc_mtu}#{', tincd restarted' if ENV['RESTART'] == '1'}"
      end
    end

    desc "Push check_mk agent plugins to live hosts over SSH (no image rebuild/redeploy). Set HOST_ID=<id> to target a single host."
    task :deploy_check_mk_plugins => [:environment] do
      hosts = if ENV['HOST_ID'].present?
        [CloudModel::Host.find(ENV['HOST_ID'])]
      else
        # Skip hosts that aren't up yet — they have no reachable agent.
        CloudModel::Host.all.reject { |host| [:booting, :not_started].include? host.deploy_state }
      end

      if hosts.empty?
        abort "No hosts found in #{Rails.env} database — forgot RAILS_ENV=production?"
      end

      failures = 0
      hosts.each do |host|
        print "#{host.name}: "
        begin
          CloudModel::Workers::HostWorker.new(host).deploy_check_mk_plugins
          puts "\e[32mOK\e[39m"
        rescue => e
          failures += 1
          puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message})"
        end
      end

      puts "\nDeployed check_mk plugins to #{hosts.size - failures}/#{hosts.size} host(s)."
      abort "#{failures} host(s) failed" if failures > 0
    end

    desc "Install unattended security upgrades on live hosts (package + apt.conf.d, no reboot, ZFS/kernel excluded). Set HOST_ID=<id> to target a single host."
    task :deploy_unattended_upgrades => [:environment] do
      hosts = if ENV['HOST_ID'].present?
        [CloudModel::Host.find(ENV['HOST_ID'])]
      else
        CloudModel::Host.all.reject { |host| [:booting, :not_started].include? host.deploy_state }
      end
      abort "No hosts found in #{Rails.env} database — forgot RAILS_ENV=production?" if hosts.empty?

      failures = 0
      hosts.each do |host|
        print "#{host.name}: "
        begin
          CloudModel::Workers::HostWorker.new(host).deploy_unattended_upgrades_to_host
          puts "\e[32mOK\e[39m"
        rescue => e
          failures += 1
          puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message})"
        end
      end
      puts "\nUnattended security upgrades on #{hosts.size - failures}/#{hosts.size} host(s)."
      abort "#{failures} host(s) failed" if failures > 0
    end

    desc "Push the host-to-host ZFS sync key to live hosts ahead of time (private key, forced-command wrapper, restricted authorized_keys entry). Optional: the first sync between two hosts pushes it on demand; this just does it for all hosts at once. Generates the key pair on first use. Set HOST_ID=<id> to target a single host."
    task :deploy_zfs_sync_key => [:environment] do
      hosts = if ENV['HOST_ID'].present?
        [CloudModel::Host.find(ENV['HOST_ID'])]
      else
        CloudModel::Host.all.reject { |host| [:booting, :not_started].include? host.deploy_state }
      end

      if hosts.empty?
        abort "No hosts found in #{Rails.env} database — forgot RAILS_ENV=production?"
      end

      failures = 0
      hosts.each do |host|
        print "#{host.name}: "
        begin
          CloudModel::Workers::HostWorker.new(host).deploy_zfs_sync_key
          puts "\e[32mOK\e[39m"
        rescue => e
          failures += 1
          puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message})"
        end
      end

      puts "\nDeployed the ZFS sync key to #{hosts.size - failures}/#{hosts.size} host(s). Syncs between two hosts that both have it now go direct."
      abort "#{failures} host(s) failed" if failures > 0
    end

    desc "Make sure the guest templates used on a host exist as ZFS build volumes there (migration from tarball-built templates; builds on the configured build host and syncs via zfs send/receive). Set HOST_ID=<id> to target a single host."
    task :prepare_zfs_templates => [:environment] do
      hosts = if ENV['HOST_ID'].present?
        [CloudModel::Host.find(ENV['HOST_ID'])]
      else
        CloudModel::Host.all.reject { |host| [:booting, :not_started].include? host.deploy_state }
      end

      if hosts.empty?
        abort "No hosts found in #{Rails.env} database — forgot RAILS_ENV=production?"
      end

      failures = 0
      hosts.each do |host|
        puts "#{host.name}:"
        # guest.template picks (and if necessary registers) the current
        # template for the guest's component set
        host.guests.map(&:template).uniq.each do |template|
          print "  #{template.name}: "
          begin
            template.ensure_build_volume! host
            puts "\e[32mOK\e[39m"
          rescue Exception => e
            failures += 1
            puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message})"
          end
        end
      end

      abort "#{failures} template volume(s) failed" if failures > 0
    end
  end

  # namespace :host_template do
  #   task :load_host do
  #     @host = CloudModel::Host.find(ENV['HOST_ID'])
  #     @template = CloudModel::HostTemplate.find(ENV['TEMPLATE_ID'])
  #     @host_template_worker = CloudModel::Workers::HostTemplateWorker.new @host
  #   end
  #
  #   desc "Build host template"
  #   task :build => [:environment, :load_host] do
  #     @host_template_worker.build_template @template
  #   end
  # end

  # namespace :guest_core_template do
  #   task :load_host do
  #     @host = CloudModel::Host.find(ENV['HOST_ID'])
  #     @template = CloudModel::GuestCoreTemplate.find(ENV['TEMPLATE_ID'])
  #     @guest_template_worker = CloudModel::Workers::GuestTemplateWorker.new @host
  #   end
  #
  #   desc "Build guest core template"
  #   task :build => [:environment, :load_host] do
  #     @guest_template_worker.build_core_template @template
  #   end
  # end

  # namespace :guest_template do
  #   task :load_host do
  #     @host = CloudModel::Host.find(ENV['HOST_ID'])
  #     @template = CloudModel::GuestTemplate.find(ENV['TEMPLATE_ID'])
  #     @guest_template_worker = CloudModel::Workers::GuestTemplateWorker.new @host
  #   end
  #
  #   desc "Build guest template"
  #   task :build => [:environment, :load_host] do
  #     @guest_template_worker.build_template @template
  #   end
  # end

  namespace :guest do
    task :load_guest do
      @guest_worker = CloudModel::Workers::GuestWorker.new CloudModel::Guest.find(ENV['GUEST_ID'])
    end

    # desc "Deploy guest with id given as guest_id"
    # task :deploy => [:environment, :load_guest] do
    #   @guest_worker.deploy
    # end
    #
    # desc "Redeploy guest with id given as guest_id"
    # task :redeploy => [:environment, :load_guest] do
    #   @guest_worker.redeploy
    # end
    #
    # desc "Redeploy many guest with ids given as guest_ids"
    # task :redeploy_many => [:environment] do
    #   guests_by_hosts = {}
    #   ids = ENV['GUEST_IDS'].split('\ ')
    #
    #   CloudModel::Guest.where(:id.in => ids).to_a.each do |guest|
    #     if guest.deploy_state == :pending
    #       guests_by_hosts[guest.host_id] ||= []
    #       guests_by_hosts[guest.host_id] << guest
    #     end
    #   end
    #
    #   guests_by_hosts.each do |host_id, guests|
    #     # TODO: Multithread redeploy (thread per host)
    #     puts "** Deploy on Host #{host_id}"
    #     guests.each do |guest|
    #       puts "=> Redeploy Guest '#{guest.name}'"
    #       @guest_worker = CloudModel::Workers::GuestWorker.new guest
    #       @guest_worker.redeploy
    #     end
    #   end
    # end

    desc "Backup guest"
    task :backup => [:environment, :load_guest] do
      @guest_worker.guest.backup
    end

    desc "Install unattended security upgrades in running guests (package + apt.conf.d, no reboot). Set GUEST_ID=<id> to target a single guest."
    task :deploy_unattended_upgrades => [:environment] do
      guests = if ENV['GUEST_ID'].present?
        [CloudModel::Guest.find(ENV['GUEST_ID'])]
      else
        CloudModel::Guest.all.select { |guest| guest.up_state == :started }
      end
      abort "No running guests found in #{Rails.env} database — forgot RAILS_ENV=production?" if guests.empty?

      failures = 0
      guests.each do |guest|
        print "#{guest.name} @ #{guest.host.name}: "
        begin
          CloudModel::Workers::GuestWorker.new(guest).deploy_unattended_upgrades_to_guest
          puts "\e[32mOK\e[39m"
        rescue => e
          failures += 1
          puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message})"
        end
      end
      puts "\nUnattended security upgrades in #{guests.size - failures}/#{guests.size} guest(s)."
      abort "#{failures} guest(s) failed" if failures > 0
    end

    desc "Push the deploy keys (www authorized_keys) of the capistrano SSH groups to running guests without a redeploy. DRY_RUN=1 only lists added/removed keys; GUEST_ID=<id> or GROUP_ID=<id> to narrow."
    task :sync_authorized_keys => [:environment] do
      group_ids = ENV['GROUP_ID'].present? ? [ENV['GROUP_ID']] : nil
      pairs = CloudModel::GuestJobs::SyncAuthorizedKeysJob.services_for(group_ids)
      pairs = pairs.select { |guest, _| guest.id.to_s == ENV['GUEST_ID'] } if ENV['GUEST_ID'].present?
      abort "No running guests with capistrano SSH groups found in #{Rails.env} database — forgot RAILS_ENV=production?" if pairs.empty?

      dry_run = ENV['DRY_RUN'] == '1'
      failures = 0
      pairs.each do |guest, service|
        print "#{guest.name} @ #{guest.host.name}: "
        begin
          result = service.worker.sync_authorized_keys dry_run: dry_run
          diff = [("+ #{result[:added] * ', '}" if result[:added].any?), ("- #{result[:removed] * ', '}" if result[:removed].any?)].compact * '  '
          puts "#{result[:state]}#{"  #{diff}" unless diff.empty?}"
        rescue => e
          failures += 1
          puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message[0, 120]})"
        end
      end
      puts "\n#{pairs.size - failures}/#{pairs.size} guest(s)#{' (dry run, nothing changed)' if dry_run}."
      abort "#{failures} guest(s) failed" if failures > 0
    end

    desc "Put cloudmodel's logrotate rules for nginx into running guests with an nginx service (the distribution's file never rotated the logs). Set GUEST_ID=<id> to target a single guest."
    task :deploy_nginx_logrotate => [:environment] do
      guests = ENV['GUEST_ID'].present? ? [CloudModel::Guest.find(ENV['GUEST_ID'])] : CloudModel::Guest.all.select { |g| g.up_state == :started }
      guests = guests.select { |g| g.services.any? { |s| s.is_a?(CloudModel::Services::Nginx) } }
      abort "No running guests with nginx found in #{Rails.env} database — forgot RAILS_ENV=production?" if guests.empty?

      failures = 0
      guests.each do |guest|
        print "#{guest.name} @ #{guest.host.name}: "
        begin
          service = guest.services.detect { |s| s.is_a?(CloudModel::Services::Nginx) }
          worker = CloudModel::Workers::Services::NginxWorker.new guest.current_lxd_container, service
          if worker.deploy_logrotate_config
            puts "\e[32mOK\e[39m"
          else
            failures += 1
            puts "\e[31mlogrotate rejects the configuration\e[39m"
          end
        rescue => e
          failures += 1
          puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message[0, 120]})"
        end
      end
      puts "\nnginx logrotate rules in #{guests.size - failures}/#{guests.size} guest(s)."
      abort "#{failures} guest(s) failed" if failures > 0
    end

    # Guests with an nginx service, narrowed by HOST=<name>|HOST_ID=<id>,
    # GUEST=<name>|GUEST_ID=<id> and EXCLUDE=<name>,<name>, sorted by host and
    # name. Aborts when nothing is left (the usual cause: RAILS_ENV missing).
    def nginx_guests_from_env running_only: true, with_nginx: true
      exclude = ENV['EXCLUDE'].to_s.split(',').map(&:strip)
      guests = ENV['GUEST_ID'].present? ? [CloudModel::Guest.find(ENV['GUEST_ID'])] : CloudModel::Guest.all.to_a
      guests = guests.select { |g| g.name == ENV['GUEST'] } if ENV['GUEST'].present?
      guests = guests.select { |g| g.host_id.to_s == ENV['HOST_ID'] } if ENV['HOST_ID'].present?
      guests = guests.select { |g| g.host.name == ENV['HOST'] } if ENV['HOST'].present?
      guests = guests.reject { |g| exclude.include? g.name }
      guests = guests.select { |g| g.up_state == :started } if running_only
      guests = guests.select { |g| g.services.any? { |s| s.is_a?(CloudModel::Services::Nginx) } } if with_nginx
      abort "No #{'running ' if running_only}guests#{' with nginx' if with_nginx} found in #{Rails.env} database — forgot RAILS_ENV=production?" if guests.empty?
      guests.sort_by { |g| [g.host.name, g.name] }
    end

    desc "Bring the RVM Ruby of the running guests onto a new patch release without a redeploy: RUBY=3.4.13. Dry run (inventory and plan) unless CONFIRM=1. Compiles once per os/arch on the build host in a clone of a finished guest template (RVM_UPDATE=1 runs `rvm get master` there first), syncs the ruby volume host to host, switches the RVM default and each application's .ruby-version, restarts the Passenger apps (cold start) and the job units; guests on another minor line are skipped; the old Ruby stays as rollback. HOST=<name>|HOST_ID=<id>, GUEST=<name>|GUEST_ID=<id> and EXCLUDE=<name>,<name> narrow the set."
    task :patch_ruby => [:environment] do
      abort "RUBY=<version> missing (e.g. RUBY=3.4.13)" if ENV["RUBY"].blank?
      guests = CloudModel::RubyPatch.guests_with_ruby nginx_guests_from_env(with_nginx: false)
      abort "No running guests with a Ruby found in #{Rails.env} database" if guests.empty?

      dry_run = ENV["CONFIRM"] != "1"
      puts "\e[33mDRY RUN — set CONFIRM=1 to patch.\e[39m" if dry_run
      patch = CloudModel::RubyPatch.new version: ENV["RUBY"], rvm_update: ENV["RVM_UPDATE"] == "1"
      counts = patch.patch! guests, dry_run: dry_run
      puts "\n#{counts[:current]} guest(s) already on #{ENV["RUBY"]}, #{counts[:patched]} patched, #{counts[:skipped]} skipped (other minor line), #{counts[:failed]} failed#{" (dry run, nothing changed)" if dry_run}."
      abort "#{counts[:failed]} guest(s) failed" if counts[:failed] > 0
    end

    desc "Switch HTTP/2 on the TLS listeners of every nginx service: HTTP2=on|off. Dry run unless CONFIRM=1 — then the field is set on the services (and, with SYNC=1, pushed to the running guests through the live sync of cloudmodel.conf; without SYNC the service is marked staged and `sync_nginx_config FILES=cloudmodel.conf` or the next deploy makes it live). FORCE=1 lets the sync overwrite a manually edited or never recorded cloudmodel.conf. HOST=<name>|HOST_ID=<id>, GUEST=<name>|GUEST_ID=<id> and EXCLUDE=<name>,<name> narrow the set."
    task :set_nginx_http2 => [:environment] do
      value = case ENV['HTTP2'].to_s.downcase
      when 'on', 'true', '1' then true
      when 'off', 'false', '0' then false
      else abort "HTTP2=on or HTTP2=off required"
      end
      confirm = ENV['CONFIRM'].to_s == '1'
      sync = ENV['SYNC'].to_s == '1'
      force = ENV['FORCE'].to_s == '1'

      counts = Hash.new(0)
      guests = nginx_guests_from_env(running_only: false)
      guests.each do |guest|
        service = guest.services.detect { |s| s.is_a?(CloudModel::Services::Nginx) }
        print "#{guest.name} @ #{guest.host.name}: "
        unless service.ssl_supported?
          counts[:no_tls] += 1
          puts "no TLS listener, HTTP/2 not applicable#{' (field set anyway)' if confirm && service.http2 != value}"
          service.set http2: value if confirm && service.http2 != value
          next
        end
        if service.http2 == value
          counts[:unchanged] += 1
          puts "\e[32malready #{value ? 'on' : 'off'}\e[39m"
          next
        end
        unless confirm
          counts[:pending] += 1
          puts "\e[33mwould switch HTTP/2 #{value ? 'on' : 'off'}\e[39m"
          next
        end
        service.set http2: value
        if sync && guest.up_state == :started
          begin
            worker = CloudModel::Workers::Services::NginxWorker.new guest.current_lxd_container, service
            result = worker.sync_config only: ['cloudmodel.conf'], force: force
            if [:applied, :unchanged].include? result[:state]
              # The listener is live; staged markers from other files or
              # fields are none of this task's business and stay as they are.
              counts[:synced] += 1
              puts "\e[32mHTTP/2 #{value ? 'on' : 'off'}, #{result[:state]} live\e[39m"
            else
              service.set config_staged_at: Time.now
              counts[:staged] += 1
              detail = result[:blocked].to_a.map { |b| "#{File.basename b[:path]} (#{b[:reason]})" } * ', '
              puts "\e[33mHTTP/2 #{value ? 'on' : 'off'} stored, sync #{result[:state]}\e[39m #{detail}#{result[:output].to_s.strip.lines.last.to_s.strip if result[:state] == :failed}".rstrip
            end
          rescue => e
            service.set config_staged_at: Time.now
            counts[:staged] += 1
            puts "\e[31mHTTP/2 #{value ? 'on' : 'off'} stored, sync ERROR\e[39m (#{e.class}: #{e.message[0, 160]})"
          end
        else
          service.set config_staged_at: Time.now
          counts[:staged] += 1
          puts "\e[33mHTTP/2 #{value ? 'on' : 'off'} stored, not live yet\e[39m"
        end
      end
      puts "\n#{guests.size} guest(s): #{counts.sort_by { |state, _| state.to_s }.map { |state, n| "#{n} #{state}" } * ', '}#{' (dry run, nothing changed — CONFIRM=1 to apply)' unless confirm}"
      puts "Push the stored value live with: rake cloudmodel:guest:sync_nginx_config FILES=cloudmodel.conf" if confirm && counts[:staged] > 0
    end

    desc "Push the current nginx configuration (nginx.conf, cloudmodel.conf, root location conf) to the running guests with an nginx service, without a redeploy (NginxWorker#sync_config: nginx -t with rollback, reload only when a file changed — a reload restarts the Passenger application processes). DRY_RUN=1 only reports what would change; FORCE=1 also overwrites manually edited or never recorded files; FILES=nginx.conf,cloudmodel.conf restricts the sync to these files. HOST=<name>|HOST_ID=<id> or GUEST=<name>|GUEST_ID=<id> narrow the set, EXCLUDE=<name>,<name> leaves guests out."
    task :sync_nginx_config => [:environment] do
      dry_run = ENV['DRY_RUN'].to_s == '1'
      force = ENV['FORCE'].to_s == '1'
      only = ENV['FILES'].to_s.split(',').map(&:strip).reject(&:blank?).presence
      guests = nginx_guests_from_env

      colors = {applied: 32, unchanged: 32, pending: 33, blocked: 33, skipped: 33, failed: 31, error: 31}
      counts = Hash.new(0)
      guests.each do |guest|
        print "#{guest.name} @ #{guest.host.name}: "
        begin
          service = guest.services.detect { |s| s.is_a?(CloudModel::Services::Nginx) }
          worker = CloudModel::Workers::Services::NginxWorker.new guest.current_lxd_container, service
          result = worker.sync_config force: force, dry_run: dry_run, only: only
          counts[result[:state]] += 1
          detail = case result[:state]
          when :applied then result[:applied].map { |path| File.basename path } * ', '
          when :pending then result[:pending].map { |path| File.basename path } * ', '
          when :blocked then result[:blocked].map { |b| "#{File.basename b[:path]} (#{b[:reason]})" } * ', '
          when :skipped then "none of #{result[:skipped] * ', '} is in this service's config"
          when :failed then result[:output].to_s.strip.lines.last.to_s.strip
          end
          puts "\e[#{colors[result[:state]]}m#{result[:state]}\e[39m #{detail}".rstrip
        rescue => e
          counts[:error] += 1
          puts "\e[31mERROR\e[39m (#{e.class}: #{e.message[0, 160]})"
        end
      end
      puts "\n#{guests.size} guest(s): #{counts.sort_by { |state, _| state.to_s }.map { |state, n| "#{n} #{state}" } * ', '}#{' (dry run, nothing changed)' if dry_run}"
      abort "#{counts[:failed] + counts[:error]} guest(s) failed" if counts[:failed] + counts[:error] > 0
    end

    desc "Push check_mk agent plugins into live guest containers via lxc file push (no image rebuild/redeploy). Set GUEST_ID=<id> to target a single guest."
    task :deploy_check_mk_plugins => [:environment] do
      guests = if ENV['GUEST_ID'].present?
        [CloudModel::Guest.find(ENV['GUEST_ID'])]
      else
        # Only running containers have a reachable agent.
        CloudModel::Guest.all.select { |guest| guest.up_state == :started }
      end

      if guests.empty?
        abort "No running guests found in #{Rails.env} database — forgot RAILS_ENV=production?"
      end

      failures = 0
      guests.each do |guest|
        print "#{guest.name} @ #{guest.host.name}: "
        begin
          CloudModel::Workers::GuestWorker.new(guest).deploy_check_mk_plugins
          puts "\e[32mOK\e[39m"
        rescue => e
          failures += 1
          puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message})"
        end
      end

      puts "\nDeployed check_mk plugins to #{guests.size - failures}/#{guests.size} guest(s)."
      abort "#{failures} guest(s) failed" if failures > 0
    end

    # Perfect for call by crontab
    # bash -c 'cd /var/www/rails/current && RAILS_ENV=production /usr/local/bin/bundle exec rake cloudmodel:guest:backup_all'
    desc "Backup all guest (the nightly maintenance run: patches the MongoDB packages replica-set-aware first when CloudModel.config.mongodb_unattended is on)"
    task :backup_all => [:environment] do
      with_backup_run_lock do
        if CloudModel.config.mongodb_unattended
          puts "== MongoDB patch run (#{Time.now.utc.strftime('%F %T')} UTC)"
          counts = CloudModel::MongodbPatch.nightly!
          puts "MongoDB: #{counts[:current]} current, #{counts[:patched]} patched, #{counts[:skipped]} skipped, #{counts[:deferred]} deferred to the next night, #{counts[:failed]} failed.\n\n" if counts
        end
        total = CloudModel::Guest.count + CloudModel::MongodbReplicationSet.where(has_backups: true).count
        with_tracked_backup_run total do
          CloudModel::Guest.backup_all
          CloudModel::MongodbReplicationSet.backup_all
          CloudModel::BackupCleanup.run_after_backup
        end
      end
    end

    desc "Build guest image"
    task :build_image => [:environment, :load_guest] do
      @guest_worker.build_image
    end
  end

  namespace :web_image do
    desc "Build a single WebImage (all its per-arch artifacts). Set WEB_IMAGE_ID=<id>."
    task :build => [:environment] do
      raise "No env variable WEB_IMAGE_ID given" unless ENV['WEB_IMAGE_ID']
      CloudModel::WebImage.find(ENV['WEB_IMAGE_ID']).build! force: true
    end

    desc "Redeploy a single WebImage to all guests using it. Set WEB_IMAGE_ID=<id>."
    task :redeploy => [:environment] do
      raise "No env variable WEB_IMAGE_ID given" unless ENV['WEB_IMAGE_ID']
      CloudModel::WebImage.find(ENV['WEB_IMAGE_ID']).redeploy! force: true
    end

    desc "Rebuild every WebImage as a ZFS app artifact per arch it is consumed on (shared build-env, decoupled from guest templates). Dry-run unless CONFIRM=1; set WEB_IMAGE_ID=<id> to target a single image."
    task :rebuild_all => [:environment] do
      images = if ENV['WEB_IMAGE_ID'].present?
        [CloudModel::WebImage.find(ENV['WEB_IMAGE_ID'])]
      else
        CloudModel::WebImage.all.to_a
      end

      abort "No web images found in #{Rails.env} database — forgot RAILS_ENV=production?" if images.empty?

      dry_run = ENV['CONFIRM'] != '1'
      puts "\e[33mDRY RUN — set CONFIRM=1 to actually build.\e[39m" if dry_run

      failures = 0
      images.each do |image|
        targets = image.build_targets
        if targets.empty?
          puts "#{image.name}: \e[33mskipped\e[39m (no guest uses it)"
          next
        end
        targets.each do |arch|
          host = CloudModel::Host.build_host(arch)
          label = "#{image.name} [#{arch}] on #{host&.name || '???'}"
          if host.nil?
            failures += 1
            puts "  #{label}: \e[31mFAILED\e[39m (no build host for arch '#{arch}')"
            next
          end
          if dry_run
            puts "  #{label}: would build"
            next
          end
          print "  #{label}: "
          begin
            image.worker(host).build_app_volume arch, force: true
            if image.reload.build_state == :finished
              puts "\e[32mOK\e[39m"
            else
              failures += 1
              puts "\e[31mFAILED\e[39m (#{image.build_last_issue})"
            end
          rescue Exception => e
            failures += 1
            puts "\e[31mFAILED\e[39m (#{e.class}: #{e.message})"
          end
        end
      end

      abort "#{failures} web image build(s) failed" if failures > 0 && !dry_run
    end
  end

  namespace :solr_image do
    task :load_solr_image do
      raise "No env variable SOLR_IMAGE_ID given" unless ENV['SOLR_IMAGE_ID']
      @solr_image_worker = CloudModel::Workers::SolrImageWorker.new CloudModel::SolrImage.find(ENV['SOLR_IMAGE_ID'])
    end
    #
    # desc "Build SolrImage"
    # task :build => [:environment, :load_solr_image] do
    #   @solr_image_worker.build
    # end

    desc "Redeploy app to all guests using SolrImage"
    task :redeploy => [:environment, :load_solr_image] do
      @solr_image_worker.redeploy
    end
  end

  # namespace :services do
  #   namespace :nginx do
  #     task :load_web_image do
  #       raise "No env variable GUEST_ID given" unless ENV['GUEST_ID']
  #       raise "No env variable SERVICE_ID given" unless ENV['SERVICE_ID']
  #       @guest = CloudModel::Guest.find ENV['GUEST_ID']
  #       @nginx_service = @guest.services.find ENV['SERVICE_ID']
  #       raise "Not an nginx service with webimage" unless @nginx_service._type == "CloudModel::Services::Nginx" and @nginx_service.web_image_id
  #
  #       @nginx_worker = CloudModel::Workers::Services::NginxWorker.new @nginx_service
  #     end
  #
  #     desc "Redeploy app to Nginx"
  #     task :redeploy => [:environment, :load_web_image] do
  #       @nginx_worker.redeploy
  #     end
  #
  #   end
  # end

end