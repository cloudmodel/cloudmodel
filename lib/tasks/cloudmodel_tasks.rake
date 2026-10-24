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

    desc "Update tinc host files"
    task :update_tinc_host_files => [:environment, :load_host] do
      @host_worker.update_tinc_host_files
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
    desc "Backup all guest"
    task :backup_all => [:environment] do
      with_backup_run_lock do
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