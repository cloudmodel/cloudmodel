require 'fileutils'
require 'net/http'
require 'net/sftp'

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
    
    def local_exec command
      Rails.logger.debug "LOKAL EXEC: #{command}"
      result = `#{command}`
      Rails.logger.debug "    #{result}"
      result
    end
  
    def build_tar_bz2 src, dst, options = {}
      def parse_param param, value
        params = ''
      
        if value == true
          params << "--#{param} "
        elsif value.class == Array
          value.each do |i|
            params << parse_param(param, i)
          end
        else
          params << "--#{param}=#{value.shellescape} "
        end
      
        params
      end
        
      cmd = "tar cjf #{dst.shellescape} "

      options.each do |k,v|
        param = k.to_s.gsub('_', '-').shellescape
      
        cmd << parse_param(param, v)
      end
      cmd << "#{src.shellescape}"
      @host.exec! cmd, "Failed to build tar #{dst}"
    end
    
    def mkdir_p path
      @host.exec! "mkdir -p #{path.shellescape}", "Failed to make directory #{path}"
    end
  
    def create_image
      #
      # Create boot image
      #
      
      @host.mount_boot_fs
      build_tar_bz2 '/boot', "/inst/boot.tar.bz2", one_file_system: true
      @host.exec 'umount /boot'
    
      #
      # Create root image
      #
      
      build_tar_bz2 '/', "/inst/root.tar.bz2", one_file_system: true, exclude: [
        '/etc/udev/rules.d/70-persistent-net.rules',
        '/tmp/*',
        '/var/tmp/*',
        '/var/cache/*',
        '/usr/portage/distfiles/*',
        '/var/log/*',
        '/inst/*', 
        '/vm/*',
        '/etc/libvirt/lxc/*',
        '/etc/tinc/vpn/*',
        '/usr/share/man',
        '/usr/share/doc',
        '/usr/portage'
      ]
    
      #
      # Download files to local /inst
      #
      
      `mkdir -p #{CloudModel.config.data_directory.shellescape}/inst`
      @host.ssh_connection.sftp.download! "/inst/boot.tar.bz2", "#{CloudModel.config.data_directory}/inst/boot.tar.bz2"
      @host.ssh_connection.sftp.download! "/inst/root.tar.bz2", "#{CloudModel.config.data_directory}/inst/root.tar.bz2"
      
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
      
      rules = {
        @host.primary_address.ip  => {
          'interface' => 'eth0',
          'services' => {
            'ssh' => {
              'port' => 22
            },
            'tinc-tcp' => {
              'port' => 655,
              'proto' => 'tcp'
            },
            'tinc-udp' => {
              'port' => 655,
              'proto' => 'udp'
            }
          }
        }
      }
    
      @host.addresses.each do |address|
        address.list_ips.each do |ip|
          rules[ip] = {
            'interface' => 'eth0',
            'services' => {}
          }
        
          if guest = @host.guests.where(external_address: ip).first
            rules[ip]['nat'] = guest.private_address
          
            services = guest.services.where(public_service: true).to_a
            services.each do |service|
              rules[ip]['services']["#{service.kind}"] ||= {}
              rules[ip]['services']["#{service.kind}"]['port'] ||= []
              rules[ip]['services']["#{service.kind}"]['port'] << service.port
    
              if service.try :ssl_port and service.try :ssl_supported
                rules[ip]['services']["#{service.kind}s"] ||= {}
                rules[ip]['services']["#{service.kind}s"]['port'] ||= []
                rules[ip]['services']["#{service.kind}s"]['port'] << service.ssl_port
              end
            end
          end
        end
      end
      
      init_script = CloudModel::FirewallWorker.new(rules).init_script
    
      mkdir_p "#{root}/etc/init.d/"
      @host.ssh_connection.sftp.file.open("#{root}/etc/init.d/cloudmodel", 'w', 0700) do |f|
        f.puts init_script
      end
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
        
        @host.ssh_connection.sftp.file.open("#{root}/etc/libvirt/lxc/#{guest.name}.xml", 'w', permissions: 0600) do |f|
          f.puts render("/cloud_model/host/etc/libvirt/lxc/guest.xml", guest: guest)
        end

        #
        # Link maschine to /etc/libvirt/lxc/autostart/
        #
        
        @host.ssh_connection.symlink "/etc/libvirt/lxc/#{guest.name}.xml", "#{root}/etc/libvirt/lxc/autostart/#{guest.name}.xml"
        
        #
        # Make dir for vm root
        #
        
        mkdir_p "#{root}/vm/#{guest.name}"
      end
    end
  
    def boot_deploy_root
      @host.mount_boot_fs
    
      #
      # Populate boot partition with Image
      #

      #@host.ssh_connection.sftp.upload! "#{CloudModel.config.data_directory}/inst/boot.tar.bz2", "/inst/boot.tar.bz2"
      @host.exec! "cd / && tar xjpf /inst/boot.tar.bz2", "Failed to unpack boot image!"
    
      #
      # Create grub bootstrap script
      #
      
      grub_script = "
      #!/bin/bash

      function die {
         echo $@
         exit 1
      }

      env-update
      source /etc/profile
      grub2-install /dev/sda || die 'Failed to install grub on sda'
      grub2-mkconfig -o /boot/grub/grub.cfg || die 'Failed to config grub'
      grub2-install /dev/sdb || die 'Failed to install grub on sda'
      echo 'Boot init done'
      "
    
      print '.'
      @host.ssh_connection.sftp.file.open("#{root}/root/init_boot.sh", 'w', 0775) do |f|
        f.puts grub_script
      end
      print '.'
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
      print '.'
      @host.exec! "chroot #{root} /root/init_boot.sh", "Failed to write boot config"

      @host.ssh_connection.sftp.remove! "#{root}/root/init_boot.sh"
  
      unless @debug      
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
      
      #@host.ssh_connection.sftp.upload! "#{CloudModel.config.data_directory}/inst/root.tar.bz2", "/inst/root.tar.bz2"
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
      @host.update_attribute :deploy_state, :running
      
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
        
        make_deploy_root
        make_keys
        config_deploy_root
        boot_deploy_root
      rescue Exception => e
        @host.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        raise e
        return false
      end
    end

    def redeploy
      @host.update_attribute :deploy_state, :running
      
      begin
        make_deploy_root
        copy_keys
        config_deploy_root         
        boot_deploy_root
      rescue Exception => e
        @host.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
        return false
      end    
    end
  end
end