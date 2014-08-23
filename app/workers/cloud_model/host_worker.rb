require 'fileutils'
require 'net/http'
require 'net/sftp'
require 'securerandom'

module CloudModel
  class HostWorker < BaseWorker

    def host
      @host
    end
  
    def root
      "/mnt/root-#{@timestamp}"
    end
    
    def config_firewall
      #
      # Configure firewall
      #
      
      CloudModel::FirewallWorker.new(@host).write_scripts root: root
    
      @host.exec! "ln -sf /etc/init.d/cloudmodel #{root}/etc/runlevels/default/", 'failed to add firewall to autostart'     
    end

    def config_fstab
      #
      # Configure fstab
      #
      
      render_to_remote '/cloud_model/host/etc/fstab', "#{root}/etc/fstab", host: @host, timestamp: @timestamp
    end
  
    def config_libvirt_guests
      #
      # Configure libvirt guests
      #
      
      FileUtils.rm_rf "#{root}/etc/libvirt/lxc/autostart/"
      mkdir_p "#{root}/etc/libvirt/lxc/autostart/"
      @host.guests.each do |guest|
        #
        # Generate xml file in /etc/libvirt/lxc/
        #
        
        render_to_remote "/cloud_model/host/etc/libvirt/lxc/guest.xml", "#{root}/etc/libvirt/lxc/#{guest.name}.xml", guest: guest

        #
        # Link maschine to /etc/libvirt/lxc/autostart/
        #
        
        @host.ssh_connection.sftp.symlink! "/etc/libvirt/lxc/#{guest.name}.xml", "#{root}/etc/libvirt/lxc/autostart/#{guest.name}.xml"
        
        #
        # Make dir for vm root
        #
        
        mkdir_p "#{root}/vm/#{guest.name}"
      end
    end
  
    def boot_deploy_root options={}
      @host.mount_boot_fs
    
      #
      # Populate boot partition with Image
      #
      @host.exec! "cd / && tar xjpf /inst/boot.tar.bz2", "Failed to unpack boot image!"
    
      #
      # chroot to execute grub bootstrap script
      #
      success, mtab = @host.exec('mount')
      print '.'
      
      unless @host.mount_boot_fs root
        raise "Failed to mount /boot to chroot"
      end
      
      render_to_remote "/cloud_model/host/etc/default/grub", "#{root}/etc/default/grub", root: @deploy_lv
      
      
      chroot! root, "grub2-install /dev/sda", 'Failed to install grub on sda'
      chroot! root, "grub2-mkconfig -o /boot/grub/grub.cfg", 'Failed to config grub'
      chroot! root, "grub2-install /dev/sdb", 'Failed to install grub on sda'
  
      unless options[:no_reboot]      
        @host.update_attribute :deploy_state, :booting
        
        #
        # Reboot host
        #
        
        @host.exec! 'reboot', 'Failed to reboot host'
      end
    end
  
    def update_tinc_host_files root = ''
      #
      # Update tinc host files
      #
      
      mkdir_p "#{root}/etc/tinc/vpn/hosts/"
      CloudModel::VpnClient.each do |client|
        render_to_remote "/cloud_model/host/etc/tinc/client", "#{root}/etc/tinc/vpn/hosts/#{client.name.shellescape}", client: client
      end
      
      CloudModel::Host.each do |host|
        render_to_remote "/cloud_model/host/etc/tinc/host", "#{root}/etc/tinc/vpn/hosts/#{host.name.shellescape}", host: host
      end
      
      true
    end

    def use_last_deploy_root
      real_volumes = @host.volume_groups.first.list_real_volumes
      raise 'Unable to get real volume list' unless real_volumes
      last_volume = real_volumes.keys.find_all{|i| i.to_s.match /root-*/}.sort{|a,b| b.to_s <=> a.to_s}.first.try :to_s
      if last_volume
        @timestamp = last_volume.to_s.sub /\Aroot-([0-9]*)\z/, '\1'
        @deploy_lv = CloudModel::LogicalVolume.where(name: "root-#{@timestamp}").first
        @deploy_lv.mount "#{root}"
      else
        raise 'No last deploy root lv found'
      end
    end
    
    def make_deploy_disk
      #
      # Partition disks
      #

      @host.exec! "sgdisk -go -n 1:2048:526335 -t 1:ef02 -c 1:boot -n 2:526336:67635199 -t 2:8200 -c 2:swap -N 3 -t 3:fd00 -c 3:lvm /dev/sda", "Failed to create partitions on /dev/sda"
      @host.exec! "sgdisk -go -n 1:2048:526335 -t 1:ef02 -c 1:boot -n 2:526336:67635199 -t 2:8200 -c 2:swap -N 3 -t 3:fd00 -c 3:lvm /dev/sdb", "Failed to create partitions on /dev/sdb"
             
      #
      # make raid 
      #
      # /dev/md127 is needed for /boot as grub would name it so anyway after first boot
      #
             
      if md_data = @host.exec('cat /proc/mdstat') and md_data[0] and md_data = md_data[1]
        unless md_data =~ /md127 \: active raid1 sdb1\[1\] sda1\[0\]/
          @host.exec 'mdadm --create -e1 -f /dev/md127 --level=1 --raid-devices=2 /dev/sda1 /dev/sdb1'
          
        end

        unless md_data =~ /md1 \: active raid1 sdb3\[1\] sda3\[0\]/
          @host.exec 'mdadm --create -e1 -f /dev/md1 --level=1 --raid-devices=2 /dev/sda3 /dev/sdb3'
          
        end          
      else
        raise 'Failed to stat md data'
      end                 
             
      #
      # make swap
      #
             
      @host.exec! 'mkswap /dev/sda2', 'Failed to create swap on sda'
      @host.exec! 'mkswap /dev/sdb2', 'Failed to create swap on sdb'
             
      #
      # make boot
      #
             
      @host.exec! 'mkfs.ext2 /dev/md127', 'Failed to create fs for boot'
      
      #
      # make lvm
      #
      # TODO: create vg0 if server was replaced
      
      @host.volume_groups.create! name: 'vg0', disk_device: 'md1'

      # 
      # make /inst
      # 
    
      @host.exec 'umount /inst'
      @host.exec 'lvremove -f vg0 inst' # Destroy lv inst if exists
      @host.exec! 'lvcreate -L32G -ninst vg0', 'Failed to create logical volume for /inst'
      @host.exec! 'mkfs.ext4 /dev/vg0/inst', 'Failed to create fs for /inst'
      @host.exec 'mkdir -p /inst'
      @host.exec! 'mount /dev/vg0/inst /inst', 'Failed to mount /inst'      
      
      #
      # The rest is quite similar to redeploy
      #  
      # TODO: SSH connection to new host for sync images etc. without entering password
    end
    
    def make_deploy_root
      @timestamp = Time.now.strftime '%Y%m%d%H%M%S'
      
      #
      # Create and mount deploy root
      #
      
      @deploy_lv = CloudModel::LogicalVolume.create! name: "root-#{@timestamp}", disk_space: "32G", volume_group: @host.volume_groups.first
      @deploy_lv.apply
      unless @deploy_lv.mount "#{root}"
        raise 'Failed to mount system partition'
      end
    end
    
    def populate_deploy_root
      #
      # Populate deploy root with system image
      #
      @host.exec! "cd #{root} && tar xjpf /inst/root.tar.bz2", "Failed to unpack system image!"
    
      mkdir_p "#{root}/inst"
    end
    
    def config_deploy_root
      mkdir_p "#{root}/etc/conf.d"
      
      render_to_remote "/cloud_model/host/etc/systemd/system/network.service", "#{root}/etc/systemd/system/network.service", host: @host
      chroot root, "ln -s #{root}/etc/systemd/system/network.service /etc/systemd/system/network.target.wants/"
                  
      render_to_remote "/cloud_model/support/etc/hostname", "#{root}/etc/hostname", host: @host
      render_to_remote "/cloud_model/support/etc/machine_info", "#{root}/etc/machine-info", host: @host     
      
      mkdir_p "#{root}/etc/libvirt/qemu/networks"     
      render_to_remote "/cloud_model/host/etc/libvirt/qemu/networks/default.xml", "#{root}/etc/libvirt/qemu/networks/default.xml", host: @host
      
      config_firewall

      # TINC part
      mkdir_p "#{root}/etc/tinc/vpn/"
      update_tinc_host_files root
      
      render_to_remote "/cloud_model/host/etc/tinc/tinc.conf", "#{root}/etc/tinc/vpn/tinc.conf", host: @host
      render_to_remote "/cloud_model/host/etc/tinc/tinc-up", "#{root}/etc/tinc/vpn/tinc-up", 0755, host: @host
  
      config_fstab
      config_libvirt_guests
      
      # Config /root/.ssh/authorized_keys
      unless File.exists?("#{CloudModel.config.data_directory}/keys/id_rsa")
        # Create key pair if non exists
        local_exec "mkdir -p #{CloudModel.config.data_directory.shellescape}/keys"
        local_exec "ssh-keygen -N '' -t rsa -b 4096 -f #{CloudModel.config.data_directory.shellescape}/keys/id_rsa"
      end
      ssh_dir = "#{root}/root/.ssh"
      mkdir_p ssh_dir
      
      @host.ssh_connection.sftp.upload! "#{CloudModel.config.data_directory}/keys/id_rsa.pub", "#{ssh_dir}/authorized_keys"
      
      return true
    end

    def make_keys
      render_to_remote "/cloud_model/host/etc/tinc/rsa_key.priv", "#{root}/etc/tinc/vpn/rsa_key.priv", 0600, host: @host
      # Host SSH keys will be generated on first host start
    end
    
    def copy_keys
      @host.exec! "cp -ra /etc/tinc/vpn/rsa_key.priv #{root}/etc/tinc/vpn/rsa_key.priv", "Failed to copy old tinc key"
      @host.exec! "cp -ra /etc/ssh/ #{root}/etc/ssh", "Failed to copy old ssk keys"
    end
    
    def sync_inst_images
      if CloudModel.config.skip_sync_images
        raise 'skipped'
      end
      
      @host.sync_inst_images
    end

    def deploy
      return false unless @host.deploy_state == :pending
      
      @host.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      build_start_at = Time.now
      
      steps = [
        ['Prepare disk for new system', :make_deploy_disk],
        ['Upsync system images', :sync_inst_images],
        ['Prepare volume for new system', :make_deploy_root],
        ['Populate volume with new system image', :populate_deploy_root],
        ['Config new system', :config_deploy_root],         
        ['Make crypto keys', :make_keys],
        # TODO: apply existing guests and restore backups
        ['Write boot config and reboot', :boot_deploy_root],        
      ]
      
      run_steps :deploy, steps, options
      
      @host.update_attributes deploy_state: :finished
      
      puts "Finished deploy host in #{distance_of_time_in_words_to_now build_start_at}"      
    end

    def redeploy options={}
      return false unless @host.deploy_state == :pending
      
      @host.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      build_start_at = Time.now
      
      steps = [
        ['Upsync system images', :sync_inst_images],
        ['Prepare volume for new system', :make_deploy_root],
        ['Populate volume with new system image', :populate_deploy_root],
        ['Config new system', :config_deploy_root],         
        ['Copy crypto keys from old system', :copy_keys],
        ['Write boot config and reboot', :boot_deploy_root],        
      ]
      
      run_steps :deploy, steps, options
      
      @host.update_attributes deploy_state: :finished
      
      puts "Finished redeploy host in #{distance_of_time_in_words_to_now build_start_at}" 
    end
    
  end
end