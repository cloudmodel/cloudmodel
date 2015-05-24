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
        
        return true
      rescue Exception => e
        @guest.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        CloudModel.log_exception e
        return false
      end
    end
  
    def redeploy
      return false unless @guest.deploy_state == :pending
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

    def config_firewall
      puts "    Configure Firewall"
      CloudModel::FirewallWorker.new(@host).write_scripts
      puts "      Restart Firewall"
      @host.exec! "/etc/cloud_model/firewall_stop && /etc/cloud_model/firewall_start", "Failed to restart Firewall!"
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