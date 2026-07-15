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

  namespace :cleanup do
    desc "Remove obsolete template tarballs (admin data dir + all hosts) and stale /cloud/build dirs. Dry run unless CONFIRM=1; keeps the newest KEEP (default 2) finished templates per type/arch plus everything referenced by deployed containers."
    task :templates => [:environment] do
      cleanup = CloudModel::TemplateCleanup.new keep_per_type: ENV.fetch('KEEP', 2)
      dry_run = ENV['CONFIRM'] != '1'

      puts "Keeping newest #{cleanup.keep_per_type} finished template(s) per type/arch + all container-referenced ones."
      cleanup.cleanup! dry_run: dry_run
      puts dry_run ? "\nDry run — nothing deleted. Re-run with CONFIRM=1 to delete." : "\nDone."
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