namespace :cloudmodel do
  desc "Backup marked services and volumes"
  task :backup => [:environment] do
    CloudModel::Guest.all.each do |guest|
      begin
        guest.backup
      rescue
        puts "Backup of Guest #{guest.name} failed"
      end
    end
  end

  namespace :host do
    task :load_host do
      @host_worker = CloudModel::Workers::HostWorker.new CloudModel::Host.find(ENV['HOST_ID'])
    end

    desc "Deploy host"
    task :deploy => [:environment, :load_host] do
      @host_worker.deploy
    end

    desc "Redeploy host"
    task :redeploy => [:environment, :load_host] do
      @host_worker.redeploy
    end

    desc "Update tinc host files"
    task :update_tinc_host_files => [:environment, :load_host] do
      @host_worker.update_tinc_host_files
    end
  end

  namespace :host_template do
    task :load_host do
      @host = CloudModel::Host.find(ENV['HOST_ID'])
      @template = CloudModel::HostTemplate.find(ENV['TEMPLATE_ID'])
      @host_template_worker = CloudModel::Workers::HostTemplateWorker.new @host
    end

    desc "Build host template"
    task :build => [:environment, :load_host] do
      @host_template_worker.build_template @template
    end
  end

  namespace :guest_core_template do
    task :load_host do
      @host = CloudModel::Host.find(ENV['HOST_ID'])
      @template = CloudModel::GuestCoreTemplate.find(ENV['TEMPLATE_ID'])
      @guest_template_worker = CloudModel::Workers::GuestTemplateWorker.new @host
    end

    desc "Build guest core template"
    task :build => [:environment, :load_host] do
      @guest_template_worker.build_core_template @template
    end
  end

  namespace :guest_template do
    task :load_host do
      @host = CloudModel::Host.find(ENV['HOST_ID'])
      @template = CloudModel::GuestTemplate.find(ENV['TEMPLATE_ID'])
      @guest_template_worker = CloudModel::Workers::GuestTemplateWorker.new @host
    end

    desc "Build guest template"
    task :build => [:environment, :load_host] do
      @guest_template_worker.build_template @template
    end
  end

  namespace :guest do
    task :load_guest do
      @guest_worker = CloudModel::Workers::GuestWorker.new CloudModel::Guest.find(ENV['GUEST_ID'])
    end

    desc "Deploy guest with id given as guest_id"
    task :deploy => [:environment, :load_guest] do
      @guest_worker.deploy
    end

    desc "Redeploy guest with id given as guest_id"
    task :redeploy => [:environment, :load_guest] do
      @guest_worker.redeploy
    end

    desc "Redeploy many guest with ids given as guest_ids"
    task :redeploy_many => [:environment] do
      guests_by_hosts = {}
      ids = ENV['GUEST_IDS'].split('\ ')

      CloudModel::Guest.where(:id.in => ids).to_a.each do |guest|
        if guest.deploy_state == :pending
          guests_by_hosts[guest.host_id] ||= []
          guests_by_hosts[guest.host_id] << guest
        end
      end

      guests_by_hosts.each do |host_id, guests|
        # TODO: Multithread redeploy (thread per host)
        puts "** Deploy on Host #{host_id}"
        guests.each do |guest|
          puts "=> Redeploy Guest '#{guest.name}'"
          @guest_worker = CloudModel::Workers::GuestWorker.new guest
          @guest_worker.redeploy
        end
      end
    end

    desc "Backup guest"
    task :backup => [:environment, :load_guest] do
      @guest_worker.guest.backup
    end

    # Perfect for call by crontab
    # bash -c 'cd /var/www/rails/current && RAILS_ENV=production /usr/local/bin/bundle exec rake cloudmodel:guest:backup_all'
    desc "Backup all guest"
    task :backup_all => [:environment] do
      CloudModel::Guest.all.each do |guest|
        begin
          guest.backup
        rescue
          puts "Backup of Guest #{guest.name} failed"
        end
      end
    end

    desc "Build guest image"
    task :build_image => [:environment, :load_guest] do
      @guest_worker.build_image
    end
  end

  namespace :web_image do
    task :load_web_image do
      raise "No env variable WEB_IMAGE_ID given" unless ENV['WEB_IMAGE_ID']
      @web_image_worker = CloudModel::Workers::WebImageWorker.new CloudModel::WebImage.find(ENV['WEB_IMAGE_ID'])
    end

    desc "Build WebImage"
    task :build => [:environment, :load_web_image] do
      @web_image_worker.build
    end

    desc "Redeploy app to all guests using WebImage"
    task :redeploy => [:environment, :load_web_image] do
      @web_image_worker.redeploy
    end
  end

  namespace :solr_image do
    task :load_solr_image do
      raise "No env variable SOLR_IMAGE_ID given" unless ENV['SOLR_IMAGE_ID']
      @solr_image_worker = CloudModel::Workers::SolrImageWorker.new CloudModel::SolrImage.find(ENV['SOLR_IMAGE_ID'])
    end

    desc "Build SolrImage"
    task :build => [:environment, :load_solr_image] do
      @solr_image_worker.build
    end

    desc "Redeploy app to all guests using SolrImage"
    task :redeploy => [:environment, :load_solr_image] do
      @solr_image_worker.redeploy
    end
  end

  namespace :services do
    namespace :nginx do
      task :load_web_image do
        raise "No env variable GUEST_ID given" unless ENV['GUEST_ID']
        raise "No env variable SERVICE_ID given" unless ENV['SERVICE_ID']
        @guest = CloudModel::Guest.find ENV['GUEST_ID']
        @nginx_service = @guest.services.find ENV['SERVICE_ID']
        raise "Not an nginx service with webimage" unless @nginx_service._type == "CloudModel::Services::Nginx" and @nginx_service.web_image_id

        @nginx_worker = CloudModel::Workers::Services::NginxWorker.new @nginx_service
      end

      desc "Redeploy app to Nginx"
      task :redeploy => [:environment, :load_web_image] do
        @nginx_worker.redeploy
      end

    end
  end

end