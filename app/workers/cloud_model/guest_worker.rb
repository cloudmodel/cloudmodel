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
    
    def ensure_lxd_custom_volumes
      guest.lxd_custom_volumes.each do |volume|
        unless volume.volume_exists?
          volume.create_volume!
        end
      end
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
    
    def config_guest_certificates
      guest.guest_certificates.each do |cert|
        unless cert.path_to_crt.blank?
          crt_file = "#{guest.deploy_path}#{cert.path_to_crt}"
          mkdir_p File.dirname(crt_file)
          @host.sftp.file.open(crt_file, 'w') do |f|
            f.write cert.certificate.crt
          end
          host.exec! "chown 100000:100000 #{crt_file}", "failed to set owner for #{crt_file}"
        end
      
        unless cert.path_to_key.blank?
          key_file = "#{guest.deploy_path}#{cert.path_to_key}"
          mkdir_p File.dirname(key_file)
          @host.sftp.file.open(key_file, 'w') do |f|
            f.write cert.certificate.key
          end
          host.exec! "chown 100000:100000 #{key_file}", "failed to set owner for #{key_file}"
          host.exec! "chmod 0700 #{key_file}", "failed to limit rights for #{key_file}"
        end
      end
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
         
    def deploy options={}
      return false unless guest.deploy_state == :pending or options[:force]
      
      guest.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      build_start_at = Time.now
      
      steps = [
        ['Sync template', :ensure_template, no_skip: true],
        ['Ensure LXD image', :ensure_lxd_image, no_skip: true],
        ['Create LXD container', :create_lxd_container],
        ['Ensure LXD custom volumes', :ensure_lxd_custom_volumes],
        ['Config LXD container', :config_lxd_container],
        ['Config guest services', :config_services],
        ['Config guest certificates', :config_guest_certificates],
        ['Config network', :config_network],
        ['Config firewall', :config_firewall],
        ['Launch LXD container', :start_lxd_container]
        
        # ['Prepare volume for new system', :make_deploy_root, on_skip: :use_last_deploy_root],
       #  ['Populate volume with new system image', :populate_deploy_root],
       #  ['Make crypto keys', :make_keys],
       #  ['Config new system', :config_deploy_root],
       #  # TODO: apply existing guests and restore backups
       #  ['Write boot config and reboot', :boot_deploy_root],
      ]
      
      run_steps :deploy, steps, options
      
      #guest.update_attributes deploy_state: :finished
      guest.collection.update_one({_id:  guest.id}, '$set' => { 'deploy_state_id': 0xf0 })
      #guest.update_attribute :deploy_state, :finished
      
      puts "Finished deploy host in #{distance_of_time_in_words_to_now build_start_at}"
      Rails.logger.debug "GUEST_WORKER: Deploy guest #{guest.name} on container #{@lxc.name} done in #{Time.now - build_start_at}"    
    end
  
    def redeploy options={}
      deploy options
    end
  end
end