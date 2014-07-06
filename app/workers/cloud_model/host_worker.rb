require 'fileutils'
require 'net/http'
require 'net/sftp'
require 'securerandom'

module CloudModel
  class HostWorker < BaseWorker

    def initialize(host)
      @host = host
    end

    def host
      @host
    end
  
    def root
      "/mnt/root-#{@timestamp}"
    end
    
    def create_image
      #
      # Create boot image
      #
      
      @host.mount_boot_fs
      build_tar '/boot', "/inst/boot.tar.bz2", :j, one_file_system: true
      @host.exec 'umount /boot'
    
      #
      # Create root image
      #
      
      build_tar '/', "/inst/root.tar.bz2", :j, one_file_system: true, exclude: [
        '/etc/udev/rules.d/70-persistent-net.rules',
        '/tmp/*',
        '/var/tmp/*',
        '/var/cache/*',
        '/var/log/*',
        '/inst/*', 
        '/vm/*',
        '/etc/libvirt/lxc/*',
        '/etc/tinc/vpn/*',
        '/usr/share/man',
        '/usr/share/doc',
        '/usr/portage/*'
        ], C: '/vm/build/host'
    
      #
      # Download files to local /inst
      #
      
      unless CloudModel.config.skip_sync_images
        `mkdir -p #{CloudModel.config.data_directory.shellescape}/inst`
        @host.ssh_connection.sftp.download! "/inst/boot.tar.bz2", "#{CloudModel.config.data_directory}/inst/boot.tar.bz2"
        @host.ssh_connection.sftp.download! "/inst/root.tar.bz2", "#{CloudModel.config.data_directory}/inst/root.tar.bz2"
      end
      
      return true
    end
  
    def copy_config path
      #
      # Copy config from old host fs
      #
      @host.exec! "cp -ra #{path.shellescape} #{root}#{path.shellescape}", "Failed to copy old config #{path}"
    end
  
    def config_firewall
      #
      # Configure firewall
      #
      
      CloudModel::FirewallWorker.new(@host).write_init_script root: root
    
      @host.exec! "ln -sf /etc/init.d/cloudmodel #{root}/etc/runlevels/default/", 'failed to add firewall to autostart'     
    end

    def config_fstab
      #
      # Configure fstab
      #
      
      @host.ssh_connection.sftp.file.open("#{root}/etc/fstab", 'w') do |f|
        f.puts render('/cloud_model/host/etc/fstab', host: @host, timestamp: @timestamp)
      end
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
        
        @host.ssh_connection.sftp.file.open("#{root}/etc/libvirt/lxc/#{guest.name}.xml", 'w', 0600) do |f|
          f.puts render("/cloud_model/host/etc/libvirt/lxc/guest.xml", guest: guest)
        end

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
      unless mtab.match(/on #{root}\/proc type/)
        @host.exec! "mount -t proc none #{root}/proc", "Failed to mount /proc to chroot"
      end
      
      unless mtab.match(/on #{root}\/proc type/)
        @host.exec! "mount --rbind /dev #{root}/dev", "Failed to mount /dev to chroot"
      end
      
      unless @host.mount_boot_fs root
        raise "Failed to mount /boot to chroot"
      end
      
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
        @host.ssh_connection.sftp.file.open("#{root}/etc/tinc/vpn/hosts/#{client.name.shellescape}", 'w') do |f|
          f.puts render("/cloud_model/host/etc/tinc/client", client: client)
        end
      end
      
      CloudModel::Host.each do |host|
        @host.ssh_connection.sftp.file.open("#{root}/etc/tinc/vpn/hosts/#{host.name.shellescape}", 'w') do |f|
          f.puts render("/cloud_model/host/etc/tinc/host", host: host)
        end
      end
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
      
      #
      # Populate deploy root with system image
      #
      @host.exec! "cd #{root} && tar xjpf /inst/root.tar.bz2", "Failed to unpack system image!"
    
      mkdir_p "#{root}/inst"
    end
    
    def config_deploy_root
      mkdir_p "#{root}/etc/conf.d"
      @host.ssh_connection.sftp.file.open("#{root}/etc/conf.d/net", 'w') do |f|
        f.puts render("/cloud_model/host/etc/conf.d/net", host: @host)
      end 
      
      @host.ssh_connection.sftp.file.open("#{root}/etc/conf.d/hostname", 'w') do |f|
        f.write render("/cloud_model/host/etc/conf.d/hostname", host: @host)
      end
      
      mkdir_p "#{root}/etc/libvirt/qemu/networks"
      @host.ssh_connection.sftp.file.open("#{root}/etc/libvirt/qemu/networks/default.xml", 'w') do |f|
        f.puts render("/cloud_model/host/etc/libvirt/qemu/networks/default.xml", host: @host)
      end
      
      config_firewall

      # TINC part
      mkdir_p "#{root}/etc/tinc/vpn/"
      update_tinc_host_files root
      
      @host.ssh_connection.sftp.file.open("#{root}/etc/tinc/vpn/tinc.conf", 'w') do |f|
        f.puts render("/cloud_model/host/etc/tinc/tinc.conf", host: @host)
      end
          
      @host.ssh_connection.sftp.file.open("#{root}/etc/tinc/vpn/tinc-up", 'w', 0755) do |f|
        f.puts render("/cloud_model/host/etc/tinc/tinc-up", host: @host)
      end
  
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
      @host.ssh_connection.sftp.file.open("#{root}/etc/tinc/vpn/rsa_key.priv", 'w', 0600) do |f|
        f.puts render("/cloud_model/host/etc/tinc/rsa_key.priv", host: @host)
      end
      # Host SSH keys will be generated on first host start
    end
    
    def copy_keys
      copy_config '/etc/tinc/vpn/rsa_key.priv'
      copy_config '/etc/ssh/'
    end

    def deploy
      return false unless @host.deploy_state == :pending
      
      @host.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      begin
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
        
        @host.sync_inst_images
        make_deploy_root
        make_keys
        config_deploy_root
        boot_deploy_root
      rescue Exception => e
        CloudModel.log_exception e
        @host.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        return false
      end
    end

    def redeploy
      return false unless @host.deploy_state == :pending
      
      @host.update_attributes deploy_state: :running, deploy_last_issue: nil
      
      begin
        @host.sync_inst_images
        make_deploy_root
        copy_keys
        config_deploy_root         
        boot_deploy_root
      rescue Exception => e
        CloudModel.log_exception e
        @host.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        return false
      end    
    end
    
    def build_image      
      return false unless @host.build_state == :pending
      
      build_dir = '/vm/build/host'
 
      @host.update_attributes build_state: :running, build_last_issue: nil

      begin
        gentoo_mirrors = [
          'http://linux.rz.ruhr-uni-bochum.de/download/gentoo-mirror/',
          'http://ftp.fi.muni.cz/pub/linux/gentoo/',
          'http://ftp-stud.fht-esslingen.de/pub/Mirrors/gentoo/',
          'http://mirror.netcologne.de/gentoo/'
        ]
        
        #
        # Create and mount build root if necessary
        #
        unless @host.mounted_at? build_dir
          # begin
          #   build_lv = CloudModel::LogicalVolume.find_by(name: 'build-host')
          # rescue 
          #   build_lv = CloudModel::LogicalVolume.create! name: 'build-host', disk_space: "32G", volume_group: @host.volume_groups.first
          # end
          build_lv = CloudModel::LogicalVolume.find_or_create_by! name: 'build-host', disk_space: "32G", volume_group: @host.volume_groups.first
          build_lv.apply
          unless build_lv.mount build_dir
            raise 'Failed to mount build partition'
          end
        end

        if true
          # Find latest stage 3 image on gentoo mirror
          gentoo_release_path = 'releases/amd64/autobuilds/'
          gentoo_stage3_info = 'latest-stage3-amd64-hardened+nomultilib.txt'
          gentoo_stage3_file = Net::HTTP.get(URI.parse("#{CloudModel.config.gentoo_mirrors.first}#{gentoo_release_path}#{gentoo_stage3_info}")).lines.last.strip.shellescape
        
          # Download and unpack stage 3
          @host.exec! "curl #{CloudModel.config.gentoo_mirrors.first}#{gentoo_release_path}#{gentoo_stage3_file} -o #{build_dir}/stage3.tar.bz2", 'Could not load stage 3 file'
          # TODO: Check checksum of stage3 file
          @host.exec! "cd #{build_dir} && tar xjpf stage3.tar.bz2", 'Failed to unpack stage 3 file'
        
          @host.ssh_connection.sftp.remove! "#{build_dir}/stage3.tar.bz2"
        end
        
        # Configure gentoo parameters
        render_to_remote "/cloud_model/host/etc/portage/make.conf", "#{build_dir}/etc/portage/make.conf", 0600, host: @host, mirrors: gentoo_mirrors
        render_to_remote "/cloud_model/host/etc/portage/package.accept_keywords", "#{build_dir}/etc/portage/package.accept_keywords", 0600, host: @host, mirrors: gentoo_mirrors
        render_to_remote "/cloud_model/host/etc/portage/package.use", "#{build_dir}/etc/portage/package.use", 0600, host: @host, mirrors: gentoo_mirrors
        render_to_remote "/cloud_model/host/etc/genkernel.conf", "#{build_dir}/etc/genkernel.conf", host: @host
        mkdir_p "#{build_dir}/etc/cloud_model"
        render_to_remote "/cloud_model/host/etc/cloud_model/kernel.config", "#{build_dir}/etc/cloud_model/kernel.config", host: @host
        
        # Copy dns configuration
        @host.exec! "cp -L /etc/resolv.conf #{build_dir}/etc/", 'Failed to copy resolv.conf'
        
        # Prepare chroot by loop mounting some important devices
        unless @host.mounted_at? "#{build_dir}/proc"
          @host.exec! "mount -t proc none #{build_dir}/proc", 'Failed to mount proc to build system'
        end
        unless @host.mounted_at? "#{build_dir}/sys"
          @host.exec! "mount --rbind /sys #{build_dir}/sys", 'Failed to mount sys to build system'
        end
        unless @host.mounted_at? "#{build_dir}/dev"
          @host.exec! "mount --rbind /dev #{build_dir}/dev", 'Failed to mount dev to build system'
        end
        unless @host.mount_boot_fs build_dir
          raise "Failed to mount /boot to build system"
        end
        
        # Write script to be run in build chroot
        mkdir_p "#{build_dir}/usr/portage"
        if true
          chroot! build_dir, "emerge-webrsync", 'Failed to sync portage'
          chroot! build_dir, "emerge --sync --quiet", 'Failed to sync portage'
          chroot! build_dir, "emerge --oneshot portage", 'Failed to merge new portage'
          chroot! build_dir, "emerge --update --newuse --deep --with-bdeps=y @world", 'Failed to update system packages'
          chroot! build_dir, "emerge --depclean", 'Failed to clean up after updating system'

          packages = %w(
            app-portage/mirrorselect
            app-portage/gentoolkit
            sys-kernel/gentoo-sources
            sys-kernel/genkernel
            sys-apps/gptfdisk
            sys-apps/systemd
            sys-apps/dbus
            sys-kernel/linux-headers
            sys-apps/kmod
            sys-fs/lvm2
            sys-fs/mdadm
            net-firewall/iptables
            sys-apps/iproute2
            net-misc/openssh
            net-misc/tinc
            app-emulation/lxc
            app-emulation/libvirt
          )
          chroot! build_dir, "emerge --autounmask=y #{packages * ' '}", 'Failed to merge needed packages'
        end
        # Kernel config
        # Set default kernel (had a broken link after unpacking, so let's go sure)
        chroot! build_dir, "eselect kernel set 1", 'Failed to select kernel sources'
        chroot! build_dir, "genkernel --kernel-config=/etc/cloud_model/kernel.config all", 'Failed to merge kernel'
                
        
        
        @host.update_attributes build_state: :finished
      rescue Exception => e
        CloudModel.log_exception e
        @host.update_attributes build_state: :failed, build_last_issue: "#{e}"
        return false    
      end
    end
    
    def update_image
      raise 'should update system; not yet implemented'
    end
  end
end