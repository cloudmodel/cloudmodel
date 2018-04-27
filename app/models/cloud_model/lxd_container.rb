module CloudModel
  class LxdContainer
    include Mongoid::Document
    include Mongoid::Timestamps
    
    embedded_in :guest, class_name: "CloudModel::Guest"
    belongs_to :guest_template, class_name: "CloudModel::GuestTemplate"
    
    before_create :set_template_to_guest
    after_create :create_container
    before_destroy :before_destroy
    after_destroy :destroy_container
    
    def set_template_to_guest
      self.guest_template = guest.template
    end
    
    def before_destroy
      if running?
        puts "Can't destroy running container; stop it first"
        return false
      end

      true
    end
        
    def name
      "#{guest.name.shellescape}-#{created_at.try :strftime, "%Y%m%d%H%M%S"}"
    end
    
    # Command definitions
    
    def lxc command
      guest.host.exec "lxc #{command}"
    end
    
    def lxc! command, error
      guest.host.exec! "lxc #{command}", error
    end
    
    
    def import_template
      set_template_to_guest if guest_template.blank?
      lxc "image import #{guest_template.lxd_image_metadata_tarball} #{guest_template.tarball} --alias #{guest_template.lxd_alias}"    
    end
    
    def create_container
      lxc! "init #{guest_template.lxd_alias} #{name}", "Failed to init LXD container"     
    end
    
    def destroy_container
      lxc! "delete #{name}", "Failed to destroy LXD container"     
    end
      
    
    def start
      # Shutdown previous running container of guest
      guest.lxd_containers.each do |c|
        c.stop if c.running?
      end
      
      lxc "start #{name}"
    end
    
    def stop options={}
      if options[:force] or running?
        lxc "stop #{name}"
      end
    end
    
    def mount
      guest.host.exec "zfs mount guests/containers/#{name}"
    end
    
    def unmount
      guest.host.exec "zfs unmount guests/containers/#{name}"
    end
    
    def mountpoint
      "/var/lib/lxd/storage-pools/default/containers/#{name}"
    end
    
    # Get generic infos about the LXD 
    def lxd_info
      success, result = lxc "info"
      YAML.load(result).deep_transform_keys { |key| key.to_s.underscore }
    end
    
    # Get infos about the container
    def lxc_info
      success, result = lxc "info #{name}"
      YAML.load(result).deep_transform_keys { |key| key.to_s.underscore }
    end
    
    def running?
      lxc_info['status'] == "Running"
    end
    
    
    def set_config key, value
      lxc "config set #{name} #{key} #{value}"
    end
    
    def config_from_guest
      set_config 'raw.lxc', "'lxc.mount.auto = cgroup'"
      set_config 'limits.cpu', guest.cpu_count
      set_config 'limits.memory', guest.memory_size
      
      puts lxc("config device set #{name} root size #{guest.root_fs_size}") # todo: fix disk quota
      
      lxc "network attach lxdbr0 #{name} eth0"
      puts lxc("config device set #{name} eth0 ipv4.address #{guest.private_address}")
    end
  end
end
