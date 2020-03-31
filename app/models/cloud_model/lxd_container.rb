module CloudModel
  class LxdContainer
    include Mongoid::Document
    include Mongoid::Timestamps
    prepend CloudModel::SmartToString
    include ActiveModel::Validations::Callbacks
    
    embedded_in :guest, class_name: "CloudModel::Guest"
    belongs_to :guest_template, class_name: "CloudModel::GuestTemplate"
    
    before_validation :ensure_template_is_set
    after_create :create_container
    before_destroy :before_destroy
    after_destroy :destroy_container
        
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
    
    def ensure_template_is_set
      if guest_template.blank? 
        if self.persisted?
          #Rails.logger.debug "Set template to #{self.guest.template.name}"
          self.update_attribute :guest_template, self.guest.template 
        else
          self.guest_template = self.guest.template
        end
      end
      self
    end
    
    def import_template
      ensure_template_is_set
      
      Rails.logger.debug "Import #{guest_template.name} to lxd"
      lxc "image import #{guest_template.lxd_image_metadata_tarball.shellescape} #{guest_template.tarball.shellescape} --alias #{guest_template.lxd_alias.shellescape}"
      
      # TODO: check if import worked or failed with {1=>"Error: Image with same fingerprint already exists\n"}      
      true
    end
    
    def create_container
      Rails.logger.debug "Create lxd container #{name} from #{guest_template.lxd_alias} "
      lxc! "init #{guest_template.lxd_alias.shellescape} #{name}", "Failed to init LXD container"     
    end
    
    def destroy_container
      lxc "delete #{name}"#, "Failed to destroy LXD container"     
    end
      
    def start
      # Shutdown previous running container of guest
      guest.lxd_containers.each do |c|
        c.stop
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
    def live_lxc_info
      success, result = lxc "list #{name} --format yaml"
      if success
        result = YAML.load(result).first
        
        if result['container']
          container = result.delete('container')
          result = result.merge(container)
        end
        
        %w(config expanded_config).each do |field|
          config = {}
          result[field].each do |k,v|
            keys = k.split('.')
            prev = config
            keys.each_with_index do |sk,i|
              prev[sk] ||= {}
              if i + 1 == keys.size
                prev[sk] = v  
              else
                prev = prev[sk]
              end
            end
          end
        
          if config['volatile'] and config['volatile']['id_map']
            config['volatile']['id_map']['next'] = JSON.parse config['volatile']['id_map']['next'].gsub('\"', '"')
            config['volatile']['id_map']['last_state'] = JSON.parse config['volatile']['id_map']['last_state'].gsub('\"', '"')
          end
          result[field] = config
        end        
        result
      else
        {}
      end
    end
    
    def lxc_info
      guest.host.monitoring_last_check_result['system']['lxd'].find{|c| c['name'] == name} || {'name' => name, 'status' => 'Unknown'}
    end
    
    
    def running?
      if state = live_lxc_info['state']
        state['status'] == "Running"
      else
        nil
      end
    end
    
    
    def set_config key, value
      lxc "config set #{name} #{key.to_s.shellescape} #{value.to_s.shellescape}"
    end
    
    def config_from_guest
      set_config 'raw.lxc', "'lxc.mount.auto = cgroup'"
      set_config 'limits.cpu', guest.cpu_count
      set_config 'limits.memory', guest.memory_size
      
      lxc "config device set #{name} root size #{guest.root_fs_size}" # todo: fix disk quota
      
      lxc "network attach lxdbr0 #{name} eth0"
      #lxc "config set #{name} volatile.lxdbr0.hwaddr #{guest.mac_address}"
      
      # Attach custom storage volumes
      guest.lxd_custom_volumes.each do |volume|
        lxc "storage volume attach default #{volume.name} #{name} #{volume.mount_point}"
      end
    end
  end
end
