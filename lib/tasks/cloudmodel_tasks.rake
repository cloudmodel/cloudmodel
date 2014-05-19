namespace :cloudmodel do
  namespace :host do
    task :load_host do
      @host_worker = CloudModel::HostWorker.new CloudModel::Host.find(ENV['HOST_ID'])
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
    
    desc "Create new host image"
    task :create_image => [:environment, :load_host] do
      @host_worker.create_image
    end
  end
  
  namespace :guest do
    task :load_guest do
      @guest_worker = CloudModel::GuestWorker.new CloudModel::Guest.find(ENV['GUEST_ID'])
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
          @guest_worker = CloudModel::GuestWorker.new guest
          @guest_worker.redeploy
        end
      end
    end
  end
  
  namespace :web_image do
    task :load_web_image do
      @web_image_worker = CloudModel::WebImageWorker.new CloudModel::WebImage.find(ENV['WEB_IMAGE_ID'])
    end
    
    desc "Build WebImage"
    task :build => [:environment, :load_web_image] do
      @web_image_worker.build
    end
  end
  
end