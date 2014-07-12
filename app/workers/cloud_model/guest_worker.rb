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
    
    def create_image
      #
      # Create guest image
      #

      build_tar '.', "/inst/guest.tar", one_file_system: true, exclude: [
        './etc/udev/rules.d/70-persistent-net.rules',
        './tmp/*',
        './var/tmp/*',
        './var/cache/*',
        './var/log/*',
        './usr/share/man',
        './usr/share/doc',
        './usr/portage/*'
      ], C: '/vm/build/guest'

      #
      # Download file to local /inst
      #

      unless CloudModel.config.skip_sync_images
        `mkdir -p #{CloudModel.config.data_directory.shellescape}/inst`
        @host.ssh_connection.sftp.download! "/inst/guest.tar", "#{CloudModel.config.data_directory}/inst/guest.tar"
      end
      
      return true
    end
      
    def deploy
      return false unless @guest.deploy_state == :pending  
      @guest.update_attributes deploy_state: :running, deploy_last_issue: nil
      
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
        @host.sync_inst_images
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
      @host.exec "umount #{@guest.deploy_path}"
      @host.exec! "mkdir -p #{@guest.deploy_path} && mount -t #{@guest.deploy_volume.disk_format} -o noatime #{@guest.deploy_volume.device} #{@guest.deploy_path}", "Failed to mount root volume!"
    end

    def unpack_root_image
      puts "    Populate System with System Image"
      @host.exec! "cd #{@guest.deploy_path} && tar xpf /inst/guest.tar", "Failed to unpack system image!"
    end

    def config_guest
      puts "  Prepare VM"

      # Setup Net
      begin
        puts "    Write network config"      
        render_to_remote "/cloud_model/guest/etc/conf.d/network", "#{@guest.deploy_path}/etc/conf.d/network@eth0", host: @host, guest: @guest
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
          f.puts "\tPS1='\\[\\033[01;31m\\]#{@guest.name.shellescape}\\[\\033[01;34m\\] \\W \\$\\[\\033[00m\\] '"
          f.puts "else"
          f.puts "\tPS1='\\[\\033[01;32m\\]\\u@#{@guest.name.shellescape}\\[\\033[01;34m\\] \\w \\$\\[\\033[00m\\] '"
          f.puts "fi"
        end
      rescue
        raise "Failed to configure profile file!"
      end
    end

    def config_services
      puts "    Handle and config Services"
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
        f.puts render("/cloud_model/host/etc/libvirt/lxc/guest.xml", guest: @guest, skip_uuid: true)
      end
      puts "    Define VM with virsh"
      @host.exec! "virsh define /inst/tmp/#{@guest.name.shellescape}.xml", "Failed to define guest '#{@guest.name.shellescape}'"
    end
    
    def build_image      
      return false unless @guest.build_state == :pending
      
      build_dir = '/vm/build/guest'
 
      @guest.update_attributes build_state: :running, build_last_issue: nil
      
      begin
        #
        # Create and mount build root if necessary
        #
        unless @host.mounted_at? build_dir
          begin
            build_lv = CloudModel::LogicalVolume.find_by(name: 'build-guest')
          rescue 
            build_lv = CloudModel::LogicalVolume.create! name: 'build-guest', disk_space: "32G", volume_group: @host.volume_groups.first
          end

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
        
        @host.exec "rm -f #{build_dir}/etc/mtab && ln -sf /proc/self/mounts #{build_dir}/etc/mtab"
        
        # Configure gentoo parameters
        render_to_remote "/cloud_model/guest/etc/portage/make.conf", "#{build_dir}/etc/portage/make.conf", 0600, host: @host, guest: @guest
        render_to_remote "/cloud_model/guest/etc/portage/package.accept_keywords", "#{build_dir}/etc/portage/package.accept_keywords", 0600, host: @host, guest: @guest
        render_to_remote "/cloud_model/guest/etc/portage/package.use", "#{build_dir}/etc/portage/package.use", 0600, host: @host, guest: @guest
 
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
        
        # Update system software
        mkdir_p "#{build_dir}/usr/portage"
        if true
          chroot! build_dir, "emerge-webrsync", 'Failed to sync portage'
          chroot! build_dir, "emerge --sync --quiet", 'Failed to sync portage'
          chroot! build_dir, "emerge --oneshot portage", 'Failed to merge new portage'
          chroot! build_dir, "emerge --update --newuse --deep --with-bdeps=y @world", 'Failed to update system packages'
          chroot! build_dir, "emerge --depclean", 'Failed to clean up after updating system'
        end
        
        if true
          # Install guest packages
          packages = %w(
            app-portage/gentoolkit
            sys-apps/systemd
            sys-apps/dbus
            sys-kernel/linux-headers
            sys-apps/kmod
            sys-apps/iproute2
          )
          
          # MongoDB
          packages += %w(
            dev-db/mongodb
          )
          
          # TODO: nginx+passenger ebuild or other merging 
          # # NGINX \w passenger
          # packages += %w(
          #   www-servers/nginx
          # )
          packages += %w(
            dev-lang/ruby
            dev-ruby/rubygems
            dev-ruby/bundler
            net-libs/nodejs
            net-misc/curl
            dev-vcs/git
          )
          
          # Redis
          packages += %w(
            dev-db/redis
          )
          
          # SSH
          packages += %w(
            net-misc/openssh
          )

          # Tomcat
          packages += %w(
            dev-java/icedtea-bin
            www-servers/tomcat
          )
          
          #chroot! build_dir, "emerge --update --newuse --deep --autounmask=y #{packages * ' '}", 'Failed to merge needed packages'
          chroot! build_dir, "emerge --autounmask=y #{packages * ' '}", 'Failed to merge needed packages'
          chroot! build_dir, "eselect ruby set ruby21", "Failed to set ruby version to 2.1"
          chroot! build_dir, "/usr/share/tomcat-7/gentoo/tomcat-instance-manager.bash --create", 'Failed to create tomcat config'
          chroot! build_dir, "rm -rf /var/lib/tomcat-7/webapps/ROOT", "Failed to remove genuine root app for tomcat"
        end
        
        if true
          chroot! build_dir, render("/cloud_model/guest/bin/build_nginx_passenger.sh"), 'Failed to build nginx+passenger'
        end
                
        render_to_remote "/cloud_model/guest/etc/systemd/system/console-getty.service", "#{build_dir}/usr/lib/systemd/system/console-getty.service"

        render_to_remote "/cloud_model/guest/etc/systemd/system/network@.service", "#{build_dir}/etc/systemd/system/network@.service"
        chroot build_dir, "ln -s /usr/lib/systemd/system/network@.service /etc/systemd/system/multi-user.target.wants/network@eth0.service"
        
        render_to_remote "/cloud_model/guest/etc/systemd/system/mongodb.service", "#{build_dir}/etc/systemd/system/mongodb.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/redis.service", "#{build_dir}/etc/systemd/system/redis.service"
        render_to_remote "/cloud_model/guest/bin/tomcat-7", "#{build_dir}/usr/sbin/tomcat-7", 0755
        render_to_remote "/cloud_model/guest/etc/systemd/system/tomcat-7.service", "#{build_dir}/etc/systemd/system/tomcat-7.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/nginx.service", "#{build_dir}/etc/systemd/system/nginx.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/sshd.service", "#{build_dir}/etc/systemd/system/sshd.service"
        
        render_to_remote "/cloud_model/support/etc/locale.conf", "#{build_dir}/etc/locale.conf", host: @guest
        render_to_remote "/cloud_model/support/etc/vconsole.conf", "#{build_dir}/etc/vconsole.conf", host: @guest
        render_to_remote "/cloud_model/guest/etc/tmpfiles.d/nginx.conf", "#{build_dir}/etc/tmpfiles.d/nginx.conf"
        
        @guest.update_attributes build_state: :finished
      rescue Exception => e
        CloudModel.log_exception e
        @guest.update_attributes build_state: :failed, build_last_issue: "#{e}"
        return false    
      end
    end
  end
end