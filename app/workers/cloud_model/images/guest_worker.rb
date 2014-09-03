module CloudModel
  module Images
    class GuestWorker < CloudModel::Images::BaseWorker
    
      def build_type
        'guest'
      end
    
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
    
      def emerge_sys_tools
        emerge! %w(
          app-portage/gentoolkit
          sys-apps/systemd
          sys-apps/dbus
          sys-kernel/linux-headers
          sys-apps/kmod
          sys-apps/iproute2
          net-misc/curl
          dev-vcs/git
        )
      end
    
      def emerge_mongodb
        emerge! %w(
          dev-db/mongodb
        )
        render_to_remote "/cloud_model/guest/etc/systemd/system/mongodb.service", "#{build_dir}/etc/systemd/system/mongodb.service"
      end
    
      def emerge_ruby
        emerge! %w(
          dev-lang/ruby
          dev-ruby/rubygems
          net-libs/nodejs
        )
        chroot! build_dir, "gem install bundler", "Failed to install bundler"
        chroot! build_dir, "eselect ruby set ruby21", "Failed to set ruby version to 2.1"
      end
    
      def emerge_redis
        emerge! %w(
          dev-db/redis
        )
        render_to_remote "/cloud_model/support/etc/system/unit.d/restart.conf", "#{build_dir}/etc/system/redis.service.d/restart.conf"
      end
    
      def emerge_ssh
        emerge! %w(
          net-misc/openssh
        )
        render_to_remote "/cloud_model/support/etc/system/unit.d/restart.conf", "#{build_dir}/etc/system/sshd.service.d/restart.conf"  
      end

      def emerge_tomcat
        emerge! %w(
          dev-java/icedtea-bin
          www-servers/tomcat
        )
        chroot! build_dir, "/usr/share/tomcat-7/gentoo/tomcat-instance-manager.bash --create", 'Failed to create tomcat config'
        chroot! build_dir, "rm -rf /var/lib/tomcat-7/webapps/ROOT", "Failed to remove genuine root app for tomcat"
        render_to_remote "/cloud_model/guest/bin/tomcat-7", "#{build_dir}/usr/sbin/tomcat-7", 0755
        render_to_remote "/cloud_model/guest/etc/systemd/system/tomcat-7.service", "#{build_dir}/etc/systemd/system/tomcat-7.service"
      end
        
      def build_nginx_passenger
        chroot! build_dir, render("/cloud_model/guest/bin/build_nginx_passenger.sh"), 'Failed to build nginx+passenger'

        render_to_remote "/cloud_model/guest/etc/systemd/system/nginx.service", "#{build_dir}/etc/systemd/system/nginx.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/rake@.service", "#{build_dir}/etc/systemd/system/rake@.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/rake@.timer", "#{build_dir}/etc/systemd/system/rake@.timer"
        render_to_remote "/cloud_model/guest/etc/tmpfiles.d/nginx.conf", "#{build_dir}/etc/tmpfiles.d/nginx.conf"
      end
  
          
      def configure_system
        render_to_remote "/cloud_model/guest/etc/systemd/system/console-getty.service", "#{build_dir}/usr/lib/systemd/system/console-getty.service"

        render_to_remote "/cloud_model/guest/etc/systemd/system/network@.service", "#{build_dir}/etc/systemd/system/network@.service"
        chroot build_dir, "ln -s /usr/lib/systemd/system/network@.service /etc/systemd/system/multi-user.target.wants/network@eth0.service"

        render_to_remote "/cloud_model/support/etc/locale.conf", "#{build_dir}/etc/locale.conf", host: @guest
        render_to_remote "/cloud_model/support/etc/vconsole.conf", "#{build_dir}/etc/vconsole.conf", host: @guest
      end
  
      def package_root
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
      end
  
      def upload_images
        if CloudModel.config.skip_sync_images
          raise 'skipped'
        end

        @guest.update_attributes build_state: :downloading
      
        `mkdir -p #{CloudModel.config.data_directory.shellescape}/inst`
        @host.ssh_connection.sftp.download! "/inst/guest.tar", "#{CloudModel.config.data_directory}/inst/guest.tar"
      end
    
    
      def build_image options={}   
        return false unless @guest.build_state == :pending
 
        @guest.update_attributes build_state: :running, build_last_issue: nil
      
        build_start_at = Time.now
      
        steps = [
          ["Check config", :check_config],
          ["Prepare build dir", :prepare_build_dir],
          ["Get Gentoo stage3 image", [
            ["Download latest stage 3", :download_stage3],
            ["Unpack stage3 image", :unpack_stage3],
            ["Remove stage3 image", :remove_stage3],
          ]],
          ["Configure build parameters", :configure_build_system],
          ["Sync portage", [
            ["webrsync", :emerge_webrsync],
            ["sync", :emerge_sync],
          ]],
          ["Build system", [
            ["Update portage", :emerge_portage],
            ["Update base packages", :emerge_update_world],
            ["Cleanup base system", :emerge_depclean],
            ["Cleanup perl installation", :perl_cleaner],
            ["Cleanup python installation", :python_cleaner],
            ["Build system tools", :emerge_sys_tools],
            ["Build SSH", :emerge_ssh],
            ["Build ruby environment", :emerge_ruby],
            ["Build MongoDB server", :emerge_mongodb],
            ["Build Redis", :emerge_redis],
            ["Build Tomcat", :emerge_tomcat],
            ["Build Nxinx with Passenger supoort", :build_nginx_passenger],
          ]],
          ["Configure system", [
            ["Configure udev", :configure_udev],
            ["Configure systemd", :configure_systemd],
            ["Configure system", :configure_system],
            ["Add system users [TODO]", :create_system_users],
          ]],
          ["Create image files", [
            ["Create root image", :package_root],
            ["Copy image files to data directory for republication to other hosts", :upload_images],
          ]],
          ["Cleanup", :unmount_build_dir],
        ]
      
        run_steps :build, steps, options
    
        @host.update_attributes build_state: :finished
      
        puts "Finished building image in #{distance_of_time_in_words_to_now build_start_at}"
      end
      
    end
  end
end