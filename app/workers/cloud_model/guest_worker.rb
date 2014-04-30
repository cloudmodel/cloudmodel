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
      return false unless [:pending, :not_started].include? @guest.deploy_state    
      @guest.update_attribute :deploy_state, :running
      
      begin
        mk_root_fs
        mount_root_fs 
        @host.sync_inst_images
        unpack_root_image 
        write_fstab
        mount_all
        config_guest
        config_services
        config_firewall

        define_guest
        @guest.start
        @guest.update_attribute :deploy_state, :finished
        
        return true
      rescue Exception => e
        @guest.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        CloudModel.log_exception e
        return false
      end
    end
  
    def redeploy
      return false unless [:pending, :not_started].include? @guest.deploy_state 
      @guest.update_attributes deploy_state: :running
      
      begin
        @guest.deploy_path = "/vm/build/#{@guest.name}"
    
        mk_root_lv
        mk_root_fs
        mount_root_fs 
        @host.sync_inst_images
        unpack_root_image
    
        config_guest
        config_services
        config_firewall
    
        umount_all
    
        puts @guest.root_volume.device
    
        old_volume = @guest.root_volume
        @guest.root_volume = @guest.deploy_volume
    
        unless @guest.save
          raise "Failed to set new root filesystem!"
        end
    
        @guest.deploy_path = nil
        @guest.deploy_volume= nil
    
        write_fstab

        @guest.undefine
    
        umount_all
        mount_root_fs
        mount_all

        define_guest
        @guest.start
    
        puts "    Destroy old root LV #{old_volume.name}"
        @host.exec "lvremove -f #{old_volume.device}"
      
        # Get rid of old volumes
        CloudModel::LogicalVolume.where(guest_id: @guest.id).ne(_id: @guest.root_volume.id).destroy
      
        @guest.update_attributes deploy_state: :finished
        
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
        @host.exec! "umount -f #{mount[0]}", "Failed to unmount #{mount[0]}!"
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

      @host.ssh_connection.sftp.file.open("/etc/fstab", 'w') do |f|
        f.puts render('/cloud_model/host/etc/fstab', host: @host, timestamp: @timestamp)
      end
    end

    def mk_root_lv  
      deploy_volume_params = @guest.root_volume.as_json(except: [:id, :_id, :created_at, :update_at, :name])
      deploy_volume_params[:name] = "#{@guest.root_volume.name.gsub(/(-([0-9]*))$/, '')}-#{Time.now.strftime "%Y%m%d%H%M%S"}"
  
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
      puts "    Mount System FS"
      @host.exec! "mkdir -p #{@guest.deploy_path} && mount -t #{@guest.deploy_volume.disk_format} -o noatime #{@guest.deploy_volume.device} #{@guest.deploy_path}", "Failed to mount root volume!"
    end

    def unpack_root_image
      puts "    Populate System with System Image"
      @host.exec! "cd #{@guest.deploy_path} && tar xpf /inst/guest.tar", "Failed to unpack system image!"
    end

    def config_guest
      puts "  Prepare VM"

      # Setup Net
      puts "    Write network config"
      begin
        @host.ssh_connection.sftp.file.open("#{@guest.deploy_path}/etc/conf.d/net", 'w') do |f|
          f.puts "dns_servers=\"\n8.8.8.8\n8.8.4.4\n213.133.100.100\n213.133.98.98\n213.133.99.99\n\"\n\n"
          f.puts "config_eth0=\"#{@guest.private_address}/#{@host.private_network.subnet}\"\n\n"
          f.puts "routes_eth0=\"default gw #{@host.private_network.gateway}\""
        end
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure network!"
      end

      begin
        puts "    Write hostname"
        @host.ssh_connection.sftp.file.open("#{@guest.deploy_path}/etc/conf.d/hostname", 'w') do |f|
          f.puts "hostname=\"#{@guest.name}\""
        end
      rescue Exception => e
        CloudModel.log_exception e
        raise "Failed to configure hostname!"
      end

      begin
        puts "    Write hosts file"
        @host.ssh_connection.sftp.file.open("#{@guest.deploy_path}/etc/hosts", 'w') do | f |
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
    
      begin
        puts "    Append prompt to profile file"
        @host.ssh_connection.sftp.file.open("#{@guest.deploy_path}/etc/profile", "a") do |f|
          f.puts "if [[ ${EUID} == 0 ]] ; then"
          f.puts "\tPS1='\\[\\033[01;31m\\]#{@guest.name}\\[\\033[01;34m\\] \\W \\$\\[\\033[00m\\] '"
          f.puts "else"
          f.puts "\tPS1='\\[\\033[01;32m\\]\\u@#{@guest.name}\\[\\033[01;34m\\] \\w \\$\\[\\033[00m\\] '"
          f.puts "fi"
        end
      rescue
        raise "Failed to configure profile file!"
      end
    end

    def config_services
      puts "    Handle and config Services"
      guest_blackice_services = {}

      @guest.services.each do |service|
        begin
          service_worker = "CloudModel::Services::#{service.class.model_name.element.camelcase}Worker".constantize.new @guest, service
  
          service_worker.write_config
          service_worker.auto_start
          rescue Exception => e
            CloudModel.log_exception e
            raise "Failed to configure service #{service.name}"
          end
      end
    end

    def config_firewall
      puts "    Configure Firewall"
      CloudModel::FirewallWorker.new(@host).write_init_script
      puts "      Restart Firewall"
      @host.exec! "/etc/init.d/cloudmodel restart", "Failed to restart Firewall!"
    end
    
    def define_guest
      puts "  Define VM"
      puts "    Write /etc/libvirt/lxc/#{@guest.name}.xml"

      mkdir_p '/inst/tmp'
      @host.ssh_connection.sftp.file.open("/inst/tmp/#{@guest.name}.xml", 'w', 0600) do |f|
        f.puts render("/cloud_model/host/etc/libvirt/lxc/guest.xml", guest: @guest)
      end
      puts "    Define VM with virsh"
      @host.exec "virsh define /inst/tmp/#{@guest.name.shellescape}.xml"
    end
  end
end