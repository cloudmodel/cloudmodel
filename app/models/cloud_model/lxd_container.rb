module CloudModel
  class LxdContainer
    include Mongoid::Document
    include Mongoid::Timestamps
    
    embedded_in :guest, class_name: "CloudModel::Guest"
    
    after_create :create_container
    before_destroy :before_destroy
    after_destroy :destroy_container
    
    
    def before_destroy
      return false if running?

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
      lxc "image import #{guest.template.lxd_image_metadata_tarball} #{guest.template.tarball} --alias #{guest.template.lxd_alias}"    
    end
    
    def create_container
      lxc! "init #{guest.template.lxd_alias} #{name}", "Failed to init LXD container"     
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
    end
  end
end
