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
    
    def error_log_object
      guest
    end
     
    def mkdir_p path
      super path
      host.exec! "chown -R 100000:100000 #{path}", "failed to set owner for #{path}"
    end
    
    def render_to_remote template, remote_file, *param_array
      super template, remote_file, *param_array
      host.exec! "chown -R 100000:100000 #{remote_file}", "failed to set owner for #{remote_file}"
    end
    
    def download_template template
      return if CloudModel.config.skip_sync_images
      super template
      # Download build template to local distribution  
      tarball_target = "#{CloudModel.config.data_directory}#{template.lxd_image_metadata_tarball}"   
      #FileUtils.mkdir_p File.dirname(tarball_target)
      command = "scp -C -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa root@#{@host.ssh_address}:#{template.lxd_image_metadata_tarball.shellescape} #{tarball_target.shellescape}"
      Rails.logger.debug command
      local_exec! command, "Failed to download archived template"
    end
    
    def upload_template template
      return if CloudModel.config.skip_sync_images
      super template
      # Upload build template to host
      srcball_target = "#{CloudModel.config.data_directory}#{template.lxd_image_metadata_tarball}"  
      #mkdir_p File.dirname(template.tarball)
      command = "scp -C -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa #{srcball_target.shellescape} root@#{@host.ssh_address}:#{template.lxd_image_metadata_tarball.shellescape}"
      Rails.logger.debug command
      local_exec! command, "Failed to upload built template"
    end
    
    
    def ensure_template
      @template = guest.template
                  
      begin
        host.sftp.stat!("#{@template.tarball}")
        host.sftp.stat!("#{@template.lxd_image_metadata_tarball}")
      rescue
        puts '      Uploading template'
        upload_template @template
      end
    end
    
    def ensure_lxd_image  
      guest.lxd_containers.new.import_template
    end     
    
    def create_lxd_container
      @lxc = guest.lxd_containers.create! guest_template: guest.template, created_at: Time.now, updated_at: Time.now
      @lxc.mount
    end
    
    def config_lxd_container
      @lxc.config_from_guest
    end
    
    def start_lxd_container
      @lxc.unmount
      guest.start @lxc
    end
    
    
    def config_services
      #@lxc.mount
      guest.deploy_path = "#{@lxc.mountpoint}/rootfs"
      
      guest.services.each do |service|
        begin
          puts "      #{service.class.model_name.element.camelcase} '#{service.name}'"
          service_worker_class = "CloudModel::Services::#{service.class.model_name.element.camelcase}Worker".constantize
          service_worker = service_worker_class.new guest, service

          service_worker.write_config
          service_worker.auto_start
        rescue Exception => e
          CloudModel.log_exception e
          raise "Failed to configure service #{service.class.model_name.element.camelcase} '#{service.name}'"
        end
      end
      mkdir_p "#{guest.deploy_path}/usr/share/cloud_model/"
      render_to_remote "/cloud_model/guest/usr/share/cloud_model/fix_permissions.sh", "#{guest.deploy_path}/usr/share/cloud_model/fix_permissions.sh", 0755, guest: guest
      #host.exec! "chown -R 100000:100000 #{guest.deploy_path}/usr/share/cloud_model/", "failed to set owner for fix_permissions script"
      host.exec! "rm -f #{guest.deploy_path}/usr/sbin/policy-rc.d", "Failed to remove policy-rc.d"
      
      #@lxc.unmount
    end 
    
    def config_network
      mkdir_p "#{guest.deploy_path}/etc/systemd/network"
      render_to_remote "/cloud_model/support/etc/systemd/network/eth0.network", "#{guest.deploy_path}/etc/systemd/network/eth0.network", 0644, address: guest.private_address, subnet: host.private_network.subnet, gateway: host.private_address
      
      chroot guest.deploy_path, "ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/dbus-org.freedesktop.network1.service"
      chroot guest.deploy_path, "ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
      chroot guest.deploy_path, "ln -sf /lib/systemd/system/systemd-networkd.socket /etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
      mkdir_p "#{guest.deploy_path}/etc/systemd/system/network-online.target.wants"
      chroot guest.deploy_path, "ln -sf /lib/systemd/system/systemd-networkd-wait-online.service /etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
    end
    
    def config_firewall
      puts "    Configure Firewall"
      CloudModel::FirewallWorker.new(host).write_scripts
      puts "      Restart Firewall"
      host.exec! "/etc/cloud_model/firewall_stop && /etc/cloud_model/firewall_start", "Failed to restart Firewall!"
    end
    
    def config_monitoring
      # puts "    Configure Monitoring"
      # CloudModel::Guest.where('services._type' => 'CloudModel::Services::Monitoring').each do |guest|
      #   puts "      on guest #{guest.name}"
      #   begin
      #     service = guest.services.find_by(_type: 'CloudModel::Services::Monitoring').update_hosts_config!
      #     guest.exec! "/bin/systemctl restart shinken-arbiter", "Failed to restart shinken"
      #   rescue
      #     puts "        failed!"
      #   end
      # end     
    end
         
    def deploy options={}
      return false unless guest.deploy_state == :pending or options[:force]
      
      guest.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      build_start_at = Time.now
      
      steps = [
        ['Sync template', :ensure_template, no_skip: true],
        ['Ensure LXD image', :ensure_lxd_image, no_skip: true],
        ['Create LXD container', :create_lxd_container],
        ['Config LXD container', :config_lxd_container],
        ['Config guest services', :config_services],
        ['Config network', :config_network],
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
      
      guest.update_attributes deploy_state: :finished
      
      puts "Finished deploy host in #{distance_of_time_in_words_to_now build_start_at}"      
    end
  
    def redeploy options={}
      deploy options
    end
         
    # -----   
          
          
    def deploy_old
      return false unless guest.deploy_state == :pending  
      guest.update_attributes deploy_state: :running, deploy_last_issue: nil
      
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
        guest.start || raise("Failed to start VM")
        guest.update_attribute :deploy_state, :finished
        
        # update hosts for shinken
        config_monitoring
        
        return true
      rescue Exception => e
        guest.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        CloudModel.log_exception e
        return false
      end
    end
  
    def redeploy_old options={}
      return false unless guest.deploy_state == :pending or options[:force]
      guest.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      begin
        guest.deploy_path = "/vm/build/#{guest.name}"
    
        mk_root_lv
        mk_root_fs
        mount_root_fs 
        unpack_root_image
    
        config_guest
        config_services
        config_firewall
    
        umount_all
    
        old_volume = guest.root_volume
        guest.root_volume = guest.deploy_volume
    
        unless guest.save
          raise "Failed to set new root filesystem!"
        end
    
        guest.deploy_path = nil
        guest.deploy_volume= nil
    
        write_fstab

        ## TODO: One shot to update admin guest
        guest.stop!
        guest.undefine || raise("Failed to undefine guest")
    
        umount_all
        mount_root_fs
        mount_all

        define_guest
        guest.start || raise("Failed to start guest")
    
        ## TODO: This should be called after one-shot update of admin guest
        puts "    Destroy old root LV #{old_volume.name}"
        host.exec "lvremove -f #{old_volume.device}"
      
        # Get rid of old volumes
        CloudModel::LogicalVolume.where(guest_id: guest.id).ne(_id: guest.root_volume.id).destroy
      
        guest.update_attributes deploy_state: :finished
        
        # update hosts for shinken
        config_monitoring
        
        return true
      rescue Exception => e
        guest.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        CloudModel.log_exception e
        return false
      end
    end

    def config_guest_old
      puts "  Prepare VM"

      begin
        puts "    Write network config"
        mkdir_p "#{guest.deploy_path}/etc/network/interfaces.d"
        render_to_remote "/cloud_model/guest/etc/network/interfaces.d/lo", "#{guest.deploy_path}/etc/network/interfaces.d/lo"
        render_to_remote "/cloud_model/guest/etc/network/interfaces.d/eth0", "#{guest.deploy_path}/etc/network/interfaces.d/eth0", host: host, guest: guest
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure network!"
      end
      
      begin
        puts "    Write hostname"
        render_to_remote "/cloud_model/support/etc/hostname", "#{guest.deploy_path}/etc/hostname", host: guest
        render_to_remote "/cloud_model/support/etc/machine_info", "#{guest.deploy_path}/etc/machine-info", host: guest     
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure hostname!"
      end

      begin
        puts "    Write hosts file"
        host.sftp.file.open("#{guest.deploy_path}/etc/hosts", 'w') do | f |
          f.puts "127.0.0.1       localhost"
          f.puts "::1             localhost"
          host.guests.each do |guest|
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