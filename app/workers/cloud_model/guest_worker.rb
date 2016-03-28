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
          
    def deploy
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
  
    def redeploy options={}
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

    def umount_all
      puts "    Unmount everything mounted under and incl. #{@guest.deploy_path}"
    
      # Find mounted FS
      mounts = []
      success, ret = @host.exec "mount | grep ' #{@guest.deploy_path.gsub('/','\/')}[/ ]'"
    
      ret.lines.each do |line|
        parts = line.split(' ')
        mounts << [parts[2], parts[0]]
      end

      mounts.sort{|a,b| b[0] <=> a[0]}.each do |mount|
        puts "      Unmount FS #{mount[0]}"
        @host.exec "umount -f #{mount[0]}"#, "Failed to unmount #{mount[0]}!"
      end
      puts "      Unmounting done"
    end

    def mount_all    
      @guest.guest_volumes.each do |volume|
        puts "      Mount FS #{volume.logical_volume.name}"
        @host.exec! "mkdir -p #{@guest.deploy_path}/#{volume.mount_point} && mount #{@guest.deploy_path}/#{volume.mount_point}", "Failed to mount #{@guest.deploy_path}/#{volume.mount_point}"
      end
    end

    def write_fstab
      puts "  Write fstab"

      @host.sftp.file.open("/etc/fstab", 'w') do |f|
        f.puts render('/cloud_model/host/etc/fstab', host: @host, timestamp: @timestamp)
      end
    end

    def mk_root_lv  
      deploy_volume_params = @guest.root_volume.as_json(except: [:id, :_id, :created_at, :update_at, :name])
      deploy_volume_params[:name] = "#{@guest.name}-root-#{Time.now.strftime "%Y%m%d%H%M%S"}"
  
      puts "  Creating new logical volume #{deploy_volume_params[:name]}"
  
      unless @guest.deploy_volume = CloudModel::LogicalVolume.create(deploy_volume_params)
        raise "Failed to define logical root volume"
      end
    end

    def mk_root_fs 
      puts "    Make System FS"
      @host.exec! "mkfs.#{@guest.deploy_volume.disk_format} #{@guest.deploy_volume.device}",  "Failed to create root filesystem!"
    end

    def mount_root_fs 
      umount_all
      puts "    Mount System FS"
      #@host.exec "umount #{@guest.deploy_path}"
      @host.exec! "mkdir -p #{@guest.deploy_path} && mount -t #{@guest.deploy_volume.disk_format} -o noatime #{@guest.deploy_volume.device} #{@guest.deploy_path}", "Failed to mount root volume!"
    end
    
    def unpack_root_image
      
      ubuntu_version = "15.10"
      ubuntu_image = "ubuntu-core-#{ubuntu_version}-core-amd64.tar.gz"
      ubuntu_url = "http://cdimage.ubuntu.com/ubuntu-core/releases/#{ubuntu_version}/release/#{ubuntu_image}"
      
      begin
        @host.sftp.stat!("/inst/#{ubuntu_image}")
      rescue
        puts "    Download Ubutu Core #{ubuntu_version}"
        @host.exec! "cd /inst && curl #{ubuntu_url.shellescape} -o /inst/#{ubuntu_image}", "Failed to download ubuntu image"
      end

      puts "    Populate system with image"
      @host.exec! "cd #{@guest.deploy_path} && tar xzpf /inst/#{ubuntu_image}", "Failed to unpack system image!"
      # Copy resolv.conf
      @host.exec! "cp /etc/resolv.conf #{@guest.deploy_path}/etc", "Failed to copy resolve conf"
      # Enable universe sources
      @host.exec! "sed -i \"/^# deb.*universe/ s/^# //\" #{@guest.deploy_path}/etc/apt/sources.list", "Failed to activate universe sources"
      @host.exec! "sed -i \"s*http://archive.ubuntu.com/ubuntu/*#{CloudModel.config.ubuntu_mirror}*\" #{@guest.deploy_path}/etc/apt/sources.list", "Failed to set ubutu mirror"
      @host.exec! "sed -i \"s/^deb-src/# deb-src/\" #{@guest.deploy_path}/etc/apt/sources.list", "Failed to set disable deb-src" unless CloudModel.config.ubuntu_deb_src
      # Don't start services on install
      render_to_remote "/cloud_model/support/usr/sbin/policy-rc.d", "#{@guest.deploy_path}/usr/sbin/policy-rc.d", 0755
      
      
      # Update package list
      puts "    Update core system"
      chroot! @guest.deploy_path, "apt-get update && apt-get upgrade -y", "Failed to update sources"
      
      # Autologin
      puts "    Config autologin"
      mkdir_p "#{@guest.deploy_path}/etc/systemd/system/console-getty.service.d"
      render_to_remote "/cloud_model/guest/etc/systemd/system/console-getty.service.d/autologin.conf", "#{@guest.deploy_path}/etc/systemd/system/console-getty.service.d/autologin.conf"
      
      # Set locale
      chroot! @guest.deploy_path, "localedef -i en_US -c -f UTF-8 en_US.UTF-8", "Failed to define locale"
      chroot! @guest.deploy_path, "update-locale LANG=en_US.UTF-8 LC_MESSAGES=POSIX", "Failed to update locale"
     
      # Tool for setting serial console size in terminal; call on virsh console to fix terminal size
      render_to_remote "/cloud_model/guest/bin/fixterm.sh", "#{@guest.deploy_path}/bin/fixterm", 0755
     
     
      #
      # apt-get install ruby -q -y
      #
      ##   MAIL!!!
      ##
      ##   openjdk-8-jre-headless tomcat8
      ##   redis-server
      ##   mongodb
      ##   ssh (installs python, search for better alt)
      ##   shinken graphite-web python-pyxmpp
      ## 
      ## 
      ### NGINX+Passenger
      #
      # apt-get install apt-transport-https ca-certificates -y
      #  apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 561F9B9CAC40B2F7
      ## Write to /etc/apt/sources.list.d/passenger.list
      # deb https://oss-binaries.phusionpassenger.com/apt/passenger wily main
      ## Update packages including passenger
      # chown root: /etc/apt/sources.list.d/passenger.list
      # chmod 600 /etc/apt/sources.list.d/passenger.list
      # apt-get update
      ## Install
      ##   nginx-extras 
      ##   passenger (!!)
      ## 
    end

    def config_guest
      puts "  Prepare VM"

      begin
        puts "    Install network base system"
        chroot! @guest.deploy_path, "apt-get install netbase -y", "Failed to install network base system"
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

    def config_services
      puts "    Install and config Services"
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
    end 

    def config_firewall
      puts "    Configure Firewall"
      CloudModel::FirewallWorker.new(@host).write_scripts
      puts "      Restart Firewall"
      @host.exec! "/etc/cloud_model/firewall_stop && /etc/cloud_model/firewall_start", "Failed to restart Firewall!"
    end
    
    def config_monitoring
      CloudModel::Guest.where('services._type' => 'CloudModel::Services::Monitoring').each do |guest|
        service = guest.services.find_by(_type: 'CloudModel::Services::Monitoring').update_hosts_config!
        guest.exec! "/bin/systemctl restart shinken-arbiter", "Failed to restart shinken"
      end      
    end
    
    def define_guest
      puts "  Define VM"
      puts "    Write /etc/libvirt/lxc/#{@guest.name}.xml"

      mkdir_p '/inst/tmp'
      @host.sftp.file.open("/inst/tmp/#{@guest.name}.xml", 'w', 0600) do |f|
        f.puts render("/cloud_model/host/etc/libvirt/lxc/guest.xml", guest: @guest, skip_uuid: true)
      end
      puts "    Define VM with virsh"
      # Make sure it is not defined anymore
      # It can fail gracefully - fails fatal on define else
      @host.exec "virsh undefine #{@guest.name.shellescape}"
      @host.exec! "virsh define /inst/tmp/#{@guest.name.shellescape}.xml", "Failed to define guest '#{@guest.name.shellescape}'"
    end
  end
end