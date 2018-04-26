module CloudModel
  class GuestWorker < BaseWorker
 
    def initialize(guest)
      @guest = guest
      @host = @guest.host
    end
    
    def host
      @host
    end
    
    def guest
      @guest
    end
    
    def ensure_template
      @template = @guest.template
                  
      begin
        @host.sftp.stat!("#{@template.tarball}")
        @host.sftp.stat!("#{@template.lxd_image_metadata_tarball}")
      rescue
        puts '      Uploading template'
        upload_template @template
      end
    end
    
    def ensure_lcd_image  
      guest.lxd_containers.new.import_template
      #@host.exec "lxc image import #{@template.lxd_image_metadata_tarball} #{@template.tarball} --alias #{@template.template_type_id}/#{@template.id}"    
    end     
    
    def create_lxd_container
      @lxc = guest.lxd_containers.create
      #@host.exec! "lxc create #{@template.template_type_id}/#{@template.id} #{guest.name.shellescape}", "Failed to launch LXD container"
    end
    
    def config_lxd_container
      @lxc.config_from_guest
      #@host.exec! "lxc config set #{guest.name.shellescape} raw.lxc 'lxc.mount.auto = cgroup'"
      #@host.exec! "lxc config set #{guest.name.shellescape} limits.cpu #{guest.cpu_count}"
    end
    
    def start_lxd_container
      @lxc.start
      #@host.exec! "lxc start #{guest.name.shellescape}"
    end
    
    
    def config_services
      @lxc.mount
      @guest.deploy_path = "#{@lxc.mountpoint}/rootfs"
      
      @guest.services.each do |service|
        begin
          puts "      #{service.class.model_name.element.camelcase} '#{service.name}'"
          service_worker_class = "CloudModel::Services::#{service.class.model_name.element.camelcase}Worker".constantize
          service_worker = service_worker_class.new @guest, service

          service_worker.write_config
          service_worker.auto_start
        rescue Exception => e
          CloudModel.log_exception e
          raise "Failed to configure service #{service.class.model_name.element.camelcase} '#{service.name}'"
        end
      end
      mkdir_p "#{@guest.deploy_path}/usr/share/cloud_model/"
      render_to_remote "/cloud_model/guest/usr/share/cloud_model/fix_permissions.sh", "#{@guest.deploy_path}/usr/share/cloud_model/fix_permissions.sh", 0755, guest: guest 
      @host.exec! "rm -f #{@guest.deploy_path}/usr/sbin/policy-rc.d", "Failed to remove policy-rc.d"
      
      @lxc.unmount
    end 
    
    def config_firewall
      puts "    Configure Firewall"
      CloudModel::FirewallWorker.new(@host).write_scripts
      puts "      Restart Firewall"
      @host.exec! "/etc/cloud_model/firewall_stop && /etc/cloud_model/firewall_start", "Failed to restart Firewall!"
    end
    
    def config_monitoring
      puts "    Configure Monitoring"
      CloudModel::Guest.where('services._type' => 'CloudModel::Services::Monitoring').each do |guest|
        puts "      on guest #{guest.name}"
        begin 
          service = guest.services.find_by(_type: 'CloudModel::Services::Monitoring').update_hosts_config!
          guest.exec! "/bin/systemctl restart shinken-arbiter", "Failed to restart shinken"
        rescue
          puts "        failed!"
        end
      end      
    end
         
    def deploy options={}
      return false unless @host.deploy_state == :pending or options[:force]
      
      @host.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      build_start_at = Time.now
      
      steps = [
        ['Sync template', :ensure_template, no_skip: true],
        ['Ensure LXD image', :ensure_lcd_image, no_skip: true],
        ['Create LXD container', :create_lxd_container],
        ['Config LXD container', :config_lxd_container],
        ['Config guest services', :config_services],
        ['Config firewall', :config_firewall],
        ['Launch LXD container', :start_lxd_container],
        ['Config monitoring', :config_monitoring]
        
        # ['Prepare volume for new system', :make_deploy_root, on_skip: :use_last_deploy_root],
       #  ['Populate volume with new system image', :populate_deploy_root],
       #  ['Make crypto keys', :make_keys],
       #  ['Config new system', :config_deploy_root],
       #  # TODO: apply existing guests and restore backups
       #  ['Write boot config and reboot', :boot_deploy_root],
      ]
      
      run_steps :deploy, steps, options
      
      @host.update_attributes deploy_state: :finished
      
      puts "Finished deploy host in #{distance_of_time_in_words_to_now build_start_at}"      
    end
  
    def redeploy options={}
      deploy options
    end
         
    # -----   
          
          
    def deploy_old
      return false unless @guest.deploy_state == :pending  
      @guest.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      begin
        mk_root_fs
        mount_root_fs 
        unpack_root_image 
        write_fstab
        mount_all
        config_guest
        config_services
        config_firewall
        
        define_guest
        @guest.start || raise("Failed to start VM")
        @guest.update_attribute :deploy_state, :finished
        
        # update hosts for shinken
        config_monitoring
        
        return true
      rescue Exception => e
        @guest.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        CloudModel.log_exception e
        return false
      end
    end
  
    def redeploy_old options={}
      return false unless @guest.deploy_state == :pending or options[:force]
      @guest.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      begin
        @guest.deploy_path = "/vm/build/#{@guest.name}"
    
        mk_root_lv
        mk_root_fs
        mount_root_fs 
        unpack_root_image
    
        config_guest
        config_services
        config_firewall
    
        umount_all
    
        old_volume = @guest.root_volume
        @guest.root_volume = @guest.deploy_volume
    
        unless @guest.save
          raise "Failed to set new root filesystem!"
        end
    
        @guest.deploy_path = nil
        @guest.deploy_volume= nil
    
        write_fstab

        ## TODO: One shot to update admin guest
        @guest.stop!
        @guest.undefine || raise("Failed to undefine guest")
    
        umount_all
        mount_root_fs
        mount_all

        define_guest
        @guest.start || raise("Failed to start guest")
    
        ## TODO: This should be called after one-shot update of admin guest
        puts "    Destroy old root LV #{old_volume.name}"
        @host.exec "lvremove -f #{old_volume.device}"
      
        # Get rid of old volumes
        CloudModel::LogicalVolume.where(guest_id: @guest.id).ne(_id: @guest.root_volume.id).destroy
      
        @guest.update_attributes deploy_state: :finished
        
        # update hosts for shinken
        config_monitoring
        
        return true
      rescue Exception => e
        @guest.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        CloudModel.log_exception e
        return false
      end
    end

    def config_guest
      puts "  Prepare VM"

      begin
        puts "    Write network config"
        mkdir_p "#{@guest.deploy_path}/etc/network/interfaces.d"
        render_to_remote "/cloud_model/guest/etc/network/interfaces.d/lo", "#{@guest.deploy_path}/etc/network/interfaces.d/lo"
        render_to_remote "/cloud_model/guest/etc/network/interfaces.d/eth0", "#{@guest.deploy_path}/etc/network/interfaces.d/eth0", host: @host, guest: @guest
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure network!"
      end
      
      begin
        puts "    Write hostname"
        render_to_remote "/cloud_model/support/etc/hostname", "#{@guest.deploy_path}/etc/hostname", host: @guest
        render_to_remote "/cloud_model/support/etc/machine_info", "#{@guest.deploy_path}/etc/machine-info", host: @guest     
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure hostname!"
      end

      begin
        puts "    Write hosts file"
        @host.sftp.file.open("#{@guest.deploy_path}/etc/hosts", 'w') do | f |
          f.puts "127.0.0.1       localhost"
          f.puts "::1             localhost"
          @host.guests.each do |guest|
            f.puts "#{"%-15s" % guest.private_address} #{guest.name} #{guest.external_hostname}" 
          end
        end
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure hosts file!"
      end
    end
    

  end
end