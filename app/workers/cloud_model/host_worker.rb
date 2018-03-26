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
      "/mnt/newroot"
    end
    
    def config_firewall
      #
      # Configure firewall
      #
      
      CloudModel::FirewallWorker.new(@host).write_scripts root: root
    
      #@host.exec! "ln -sf /etc/init.d/cloudmodel #{root}/etc/runlevels/default/", 'failed to add firewall to autostart'     
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
        
        @host.sftp.symlink! "/etc/libvirt/lxc/#{guest.name}.xml", "#{root}/etc/libvirt/lxc/autostart/#{guest.name}.xml"
        
        #
        # Make dir for vm root
        #
        
        mkdir_p "#{root}/vm/#{guest.name}"
      end
    end
  
    def boot_deploy_root options={}
      comment_sub_step 'Ensure /boot is mounted'
      @host.unmount_boot_fs
      
      unless @host.mount_boot_fs root
        raise "Failed to mount /boot to chroot"
      end
      
      comment_sub_step 'Copy kernel and grub to /boot'
      chroot root, "cd /kernel; tar cf - * | ( cd /boot; tar xfp -)"
      
      # #
      # # chroot to execute grub bootstrap script
      # #
      # success, mtab = @host.exec('mount')
      # print '.'
           
      #render_to_remote "/cloud_model/host/etc/default/grub", "#{root}/etc/default/grub", root: @deploy_lv
      
      comment_sub_step 'Setup grub bootloader'    
      chroot! root, "grub-install  --no-floppy --recheck /dev/sda", 'Failed to install grub on sda'
      chroot! root, "grub-mkconfig -o /boot/grub/grub.cfg", 'Failed to config grub'
      chroot! root, "grub-install --no-floppy /dev/sdb", 'Failed to install grub on sda'
  
      unless options[:no_reboot]     
        comment_sub_step 'Reboot Host' 
        @host.update_attribute :deploy_state, :booting
        
        #
        # Reboot host
        #
        
        #@host.exec! 'reboot', 'Failed to reboot host'
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

    def make_deploy_disk
      #
      # Partition disks
      #
      
      comment_sub_step 'Partition disks'
      
      part_cmd = "sgdisk -go " +
        "-n 1:2048:526335 -t 1:ef02 -c 1:boot " +
        "-n 2:526336:67635199 -t 2:8200 -c 2:swap " +
        "-n 3:67635200:134744063 -t 3:fd00 -c 3:root_a " +
        "-n 4:134744064:201852927 -t 4:fd00 -c 4:root_b " +
        "-n 5:201852928:403179519 -t 5:fd00 -c 5:cloud " +
        "-N 6 -t 6:8300 -c 6:guests "
      
      @host.exec! part_cmd + "/dev/sda", "Failed to create partitions on /dev/sda"
      @host.exec! part_cmd + "/dev/sdb", "Failed to create partitions on /dev/sdb"
             
      #
      # make raid 
      #
           
      comment_sub_step 'Init RAID'    
             
      if md_data = @host.exec('cat /proc/mdstat') and md_data[0] and md_data = md_data[1]
        comment_sub_step 'Init md0 (boot)', indent: 4
        unless md_data =~ /md0 \: active raid1 sdb1\[1\] sda1\[0\]/
          @host.exec 'mdadm --zero-superblock /dev/sda1 /dev/sdb1'
          @host.exec 'mdadm --create -e1 -f /dev/md0 --level=1 --raid-devices=2 /dev/sda1 /dev/sdb1'          
        end

        comment_sub_step 'Init md1 (cloud)', indent: 4
        unless md_data =~ /md1 \: active raid1 sdb5\[1\] sda5\[0\]/
          @host.exec 'mdadm --zero-superblock /dev/sda5 /dev/sdb5'
          @host.exec 'mdadm --create -e1 -f /dev/md1 --level=1 --raid-devices=2 /dev/sda5 /dev/sdb5'         
        end       
           
        comment_sub_step 'Init md2 (root_a)', indent: 4
        unless md_data =~ /md1 \: active raid1 sdb3\[1\] sda3\[0\]/
          @host.exec 'mdadm --zero-superblock /dev/sda3 /dev/sdb3'
          @host.exec 'mdadm --create -e1 -f /dev/md2 --level=1 --raid-devices=2 /dev/sda3 /dev/sdb3'         
        end     
             
        comment_sub_step 'Init md3 (root_b)', indent: 4
        unless md_data =~ /md1 \: active raid1 sdb4\[1\] sda4\[0\]/
          @host.exec 'mdadm --zero-superblock /dev/sda4 /dev/sdb4'
          @host.exec 'mdadm --create -e1 -f /dev/md3 --level=1 --raid-devices=2 /dev/sda4 /dev/sdb4'         
        end          
      else
        raise 'Failed to stat md data'
      end                 
             
      #
      # make swap
      #
             
      comment_sub_step 'Make swap space'    
             
      @host.exec! 'mkswap /dev/sda2', 'Failed to create swap on sda'
      @host.exec! 'mkswap /dev/sdb2', 'Failed to create swap on sdb'
             
      #
      # make boot
      #
      
      comment_sub_step 'Format boot array'
             
      @host.exec! 'mkfs.ext2 /dev/md0', 'Failed to create fs for boot'

      comment_sub_step 'Format cloud array'
      # make btrfs
      @host.exec! 'mkfs.btrfs -f /dev/md1', 'Failed to create btrfs'    
      @host.exec 'mkdir -p /cloud'
      @host.exec! 'mount /dev/md1 /cloud', 'Failed to mount /cloud'      
      
      
      #
      # The rest is quite similar to redeploy
      #  
      # TODO: SSH connection to new host for sync images etc. without entering password
    end
    
    def ensure_cloud_filesystem
      unless @host.mounted_at? '/cloud'
        mkdir_p "/cloud"
        @host.exec! 'mount /dev/md1 /cloud', 'Failed to mount /cloud'
      end
    end
    
    def deploy_root_device
      if @deploy_root_device
        #debug "DRD cached"
        return @deploy_root_device
      else
        current_root_device = @host.exec('findmnt -n -o SOURCE /')[1].strip
        @deploy_root_device = "/dev/md2"
      
        if current_root_device == '/dev/md2'
          @deploy_root_device = "/dev/md3"
        end        
    
        @deploy_root_device
      end
    end
    
    def make_deploy_root
      @host.exec "umount #{deploy_root_device}"
      @host.exec "umount #{root}"
      mkdir_p root
      
      @host.exec! "mkfs.ext4 #{deploy_root_device}", "Failed to create system fs"
      @host.exec! "mount #{deploy_root_device} #{root}", "Failed to mount system fs"
    end
    
    def use_last_deploy_root
      # real_volumes = @host.volume_groups.first.list_real_volumes
     #  raise 'Unable to get real volume list' unless real_volumes
     #  last_volume = real_volumes.keys.find_all{|i| i.to_s.match /\Aroot-[0-9]*\z/}.sort{|a,b| b.to_s <=> a.to_s}.first
     #  if last_volume
     #    @timestamp = last_volume.to_s.sub /\Aroot-([0-9]*)\z/, '\1'
     #    @deploy_lv = CloudModel::LogicalVolume.where(name: "root-#{@timestamp}").first
     #    unless @deploy_lv
     #      @deploy_lv = CloudModel::LogicalVolume.new name: "root-#{@timestamp}", disk_space: real_volumes[last_volume][:l_size], volume_group: @host.volume_groups.first
     #    end
     #    @deploy_lv.mount "#{root}"
     #  else
     #    raise 'No last deploy root lv found'
     #  end
     
     unless @host.mounted_at? root
       mkdir_p root
       @host.exec "umount #{deploy_root_device}"
       @host.exec! "mount #{deploy_root_device} #{root}", "Failed to mount system fs"
     end
     
     
    end
    
    
    def populate_deploy_root  
      ensure_cloud_filesystem
         
      # make sure there is a HostTemplate and find out its tar file
      tarball = CloudModel::HostTemplate.last_useable(@host, 
        indent: current_indent + 2, 
        counter_prefix: "#{current_counter_prefix}",
        prepend_output: " [Building]\n"
      ).tarball
        
      
      #
      # Populate deploy root with system image
      #
      @host.exec! "cd #{root} && tar xpf #{tarball}", "Failed to unpack system image!"
    
      mkdir_p "#{root}/inst"
    end
    
    def config_deploy_root
      #mkdir_p "#{root}/etc/conf.d"
      
      comment_sub_step 'render network config'
      
      render_to_remote "/cloud_model/host/etc/systemd/system/network.service", "#{root}/etc/systemd/system/network.service", host: @host
      chroot root, "ln -sf /etc/systemd/system/network.service /etc/systemd/system/multi-user.target.wants/"
            
      comment_sub_step 'config hostname and machine info'      
                  
      render_to_remote "/cloud_model/support/etc/hostname", "#{root}/etc/hostname", host: @host
      render_to_remote "/cloud_model/support/etc/machine_info", "#{root}/etc/machine-info", host: @host     
            
      comment_sub_step 'config firewall'
      
      config_firewall
      
      comment_sub_step 'config lxd bridge network'
      
      render_to_remote "/cloud_model/host/etc/default/lxd-bridge", "#{root}/etc/default/lxd-bridge", host: @host
        
      comment_sub_step 'config tinc vpn hosts'

      # TINC part
      mkdir_p "#{root}/etc/tinc/vpn"
      update_tinc_host_files root
      
      comment_sub_step 'render tinc config'
      
      render_to_remote "/cloud_model/host/etc/tinc/tinc.conf", "#{root}/etc/tinc/vpn/tinc.conf", host: @host
      render_to_remote "/cloud_model/host/etc/tinc/tinc-up", "#{root}/etc/tinc/vpn/tinc-up", 0755, host: @host
  
      comment_sub_step 'render fstab'
  
      config_fstab
      
      comment_sub_step 'config guests'
      
      config_libvirt_guests
      
      
      comment_sub_step 'config ssh keys'
      # Config /root/.ssh/authorized_keys
      unless File.exists?("#{CloudModel.config.data_directory}/keys/id_rsa")
        # Create key pair if non exists
        local_exec "mkdir -p #{CloudModel.config.data_directory.shellescape}/keys"
        local_exec "ssh-keygen -N '' -t rsa -b 4096 -f #{CloudModel.config.data_directory.shellescape}/keys/id_rsa"
      end
      ssh_dir = "#{root}/root/.ssh"
      mkdir_p ssh_dir
            
      @host.sftp.upload! "#{CloudModel.config.data_directory}/keys/id_rsa.pub", "#{ssh_dir}/authorized_keys"
      
      comment_sub_step 'config exim mailer'  
          
      # Config exim form mail out
      render_to_remote "/cloud_model/host/etc/exim/exim-out.conf", "#{root}/etc/exim4/exim4.conf", host: @host
      
      comment_sub_step 'config lm_sensors'
            
      chroot root, "/usr/sbin/sensors-detect --auto"
      
      comment_sub_step 'config LXD'
      
      chroot root, "/usr/bin/lxd init --auto"
      
      
      return true
    end

    def make_keys
      mkdir_p "#{root}/etc/tinc/vpn/"
      render_to_remote "/cloud_model/host/etc/tinc/rsa_key.priv", "#{root}/etc/tinc/vpn/rsa_key.priv", 0600, host: @host
      # Host SSH keys will not be generated on first host start on Ubuntu
      chroot root, "dpkg-reconfigure openssh-server"
    end
    
    def copy_keys
      # TODO: put keys to a more failsafe location like somewhere in /inst
      
      begin
        mkdir_p "#{root}/etc/tinc/vpn/"
        @host.exec! "cp -ra /etc/tinc/vpn/rsa_key.priv #{root}/etc/tinc/vpn/rsa_key.priv", "Failed to copy old tinc key"
      rescue
        print " (old tinc key not found, create new)"
        make_keys
      end
      
      begin
        @host.exec! "cp -ra /etc/ssh/ssh_host_*key* #{root}/etc/ssh/", "Failed to copy old ssh keys"
      rescue
        print " (old ssh keys not found)"
      end
    end
    
    def sync_inst_images
      if CloudModel.config.skip_sync_images
        raise 'skipped'
      end
      
      @host.sync_inst_images
    end

    def deploy options={}
      return false unless @host.deploy_state == :pending or options[:force]
      
      @host.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      build_start_at = Time.now
      
      steps = [
        ['Prepare disk for new system', :make_deploy_disk],
        ['Upsync system images', :sync_inst_images],
        ['Prepare volume for new system', :make_deploy_root, on_skip: :use_last_deploy_root],
        ['Populate volume with new system image', :populate_deploy_root],
        ['Make crypto keys', :make_keys],
        ['Config new system', :config_deploy_root],         
        # TODO: apply existing guests and restore backups
        ['Write boot config and reboot', :boot_deploy_root],        
      ]
      
      run_steps :deploy, steps, options
      
      @host.update_attributes deploy_state: :finished
      
      puts "Finished deploy host in #{distance_of_time_in_words_to_now build_start_at}"      
    end

    def redeploy options={}
      return false unless @host.deploy_state == :pending or options[:force]
      
      @host.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      build_start_at = Time.now
      
      steps = [
        ['Upsync system images', :sync_inst_images],
        ['Prepare volume for new system', :make_deploy_root, on_skip: :use_last_deploy_root],
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