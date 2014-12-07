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
          net-analyzer/net-snmp
          mail-mta/ssmtp
        )
        # Tool for setting serial console size in terminal; call on virsh console to fix terminal size
        render_to_remote "/cloud_model/guest/bin/fixterm.sh", "#{build_dir}/bin/fixterm", 0755
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
        chroot! build_dir, "eselect ruby set ruby21", "Failed to set ruby version to 2.1"
        chroot! build_dir, "gem install bundler", "Failed to install bundler"
      end
    
      def emerge_redis
        emerge! %w(
          dev-db/redis
        )
        mkdir_p "#{build_dir}/etc/system/redis.service.d/"
        render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/redis.service.d/restart.conf"
      end
    
      def emerge_ssh
        emerge! %w(
          net-misc/openssh
        )
        mkdir_p "#{build_dir}/etc/system/sshd.service.d/"
        render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/sshd.service.d/restart.conf"  
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
      
        # mkdir -p /etc/systemd/system/timers.target.wants
        # ln -s /etc/systemd/system/rake@.timer /etc/systemd/system/timers.target.wants/rake@cloudmodel:guest:backup_all.timer
      end
  
      def emerge_shinken  
        emerge! %w(
          dev-python/cherrypy
          net-analyzer/shinken
          dev-perl/Net-SNMP
          dev-python/pip
          dev-python/pymongo

          dev-python/pycairo
          dev-python/django
        )

        python_site_packages_path = '/usr/lib/python2.7/site-packages'

        chroot! build_dir, "python2 /usr/bin/pip install daemonize", 'Unable to install python daemonize'
        chroot! build_dir, "python2 /usr/bin/pip install https://github.com/graphite-project/ceres/tarball/master", 'Unable to add graphite to pip'
        chroot! build_dir, "python2 /usr/bin/pip install whisper --install-option='--install-scripts=/usr/bin' --install-option='--install-lib=#{python_site_packages_path}' --install-option='--install-data=/var/lib/graphite'", 'Unable to install python whisper'
        chroot! build_dir, "python2 /usr/bin/pip install carbon --install-option='--install-scripts=/usr/bin' --install-option='--install-lib=#{python_site_packages_path}' --install-option='--install-data=/var/lib/graphite'", 'Unable to install python carbon'
        chroot! build_dir, "python2 /usr/bin/pip install django", 'Unable to install python django'
        chroot! build_dir, "python2 /usr/bin/pip install django-tagging", 'Unable to install python django-tagging'
        chroot! build_dir, "python2 /usr/bin/pip install uwsgi", 'Unable to install python uwsgi'
        chroot! build_dir, "python2 /usr/bin/pip install graphite-web --install-option='--install-scripts=/usr/bin' --install-option='--install-lib=#{python_site_packages_path}' --install-option='--install-data=/var/lib/graphite'", 'Unable to install python graphite-web'
        chroot! build_dir, "sed -i 's/from twisted.scripts._twistd_unix import daemonize/import daemonize/' #{python_site_packages_path}/carbon/util.py", 'Unable to patch python carbon'


        chroot! build_dir, "useradd -c 'added by cloud_model for graphite' -d /opt/graphite -s /bin/bash -r graphite", 'Failed to add user graphite'

        mkdir_p "#{build_dir}/var/lib/graphite"
        chroot! build_dir, "chown -R graphite:graphite /var/lib/graphite/storage", 'Failed to assign graphite data folder to graphite'
        mkdir_p "#{build_dir}/var/log/graphite/webapp"
        chroot! build_dir, "chown -R graphite:graphite /var/log/graphite", 'Failed to assign graphite log folder to graphite'

        fix_old_urls_import = 's/from django.conf.urls.defaults import \*/from django.conf.urls import patterns, url, include/'
        host.exec! "sed -i '#{fix_old_urls_import}' #{build_dir}/#{python_site_packages_path}/graphite/urls.py", 'Failed to patch graphite for django 1.7'
        host.exec! "for i in #{build_dir}/#{python_site_packages_path}/graphite/*/urls.py; do sed -i '#{fix_old_urls_import}' $i; done", 'Failed to patch graphite modules for django 1.7'
        render_to_remote "/cloud_model/guest/etc/graphite/web_local_settings.py", "#{build_dir}/#{python_site_packages_path}/graphite/local_settings.py", 0644

        mkdir_p "#{build_dir}/etc/tmpfiles.d"
host.exec! "echo \"D /var/run/graphite 0755 graphite graphite\" > #{build_dir}/etc/tmpfiles.d/graphite.conf", 'Failed to add graphite run directory to tmpfiles'

        render_to_remote "/cloud_model/guest/etc/systemd/system/carbon-cache.service", "#{build_dir}/usr/lib/systemd/system/carbon-cache.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/graphite-web.service", "#{build_dir}/usr/lib/systemd/system/graphite-web.service"

        mkdir_p "#{build_dir}/etc/graphite"
        render_to_remote "/cloud_model/guest/etc/graphite/carbon.conf", "#{build_dir}/etc/graphite/carbon.conf", 0544
        render_to_remote "/cloud_model/guest/etc/graphite/storage-schemas.conf", "#{build_dir}/etc/graphite/storage-schemas.conf", 0544


        chroot! build_dir, "chmod u+s /usr/lib/nagios/plugins/check_icmp", 'Unable to add su flag to icmp check'
        # chmod u+s /usr/lib/nagios/plugins/check_smart
        chroot! build_dir, "ln -sf /usr/lib/nagios/plugins/utils.* /var/lib/shinken/libexec/", 'Unable to link nagios helpers to shinken libexec'

        chroot! build_dir, "shinken --init", 'Unable to init shinken'

        chroot! build_dir, "shinken install graphite", 'Unable to install shinken graphite'
        chroot! build_dir, "shinken install mod-mongodb", 'Unable to install shinken mod-mongodb'
        chroot! build_dir, "shinken install logstore-mongodb", 'Unable to install shinken logstore-mongodb'
        chroot! build_dir, "shinken install livestatus", 'Unable to install shinken livestatus'

        chroot! build_dir, "shinken install webui", 'Unable to install shinken webui'
        chroot! build_dir, "shinken install auth-cfg-password", 'Unable to install shinken auth-cfg-password'
        chroot! build_dir, "shinken install ui-graphite", 'Unable to install shinken ui-graphite'

        chroot! build_dir, "shinken install http", 'Unable to install shinken http'
        chroot! build_dir, "shinken install ssh", 'Unable to install shinken ssh'

        chroot! build_dir, "gem install snmp", 'Unable to install ruby snmp gem'
        chroot! build_dir, "gem install redis", 'Unable to install ruby redis gem'
        chroot! build_dir, "gem install bson_ext mongo", 'Unable to install ruby mongo gem'
        chroot! build_dir, "gem install nokogiri -- --use-system-libraries", 'Unable to install ruby nokogiri gem'

        chroot! build_dir, "rm -rf /etc/shinken/hosts/localhost.cfg", "Failed to remove localhost example for shinken host"

        # render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/snmp_helpers.rb", "#{build_dir}/var/lib/shinken/libexec/snmp_helpers.rb", 0700
        # %w(cpu disks mem net_usage sensors lvm mdstat smart mongodb nginx redis tomcat).each do |check_name|
        #   render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/check_#{check_name}.rb", "#{build_dir}/var/lib/shinken/libexec/check_#{check_name}.rb", 0700
        #   render_to_remote "/cloud_model/guest/etc/shinken/commands/check_#{check_name}.cfg", "#{build_dir}/etc/shinken/commands/check_#{check_name}.cfg"
        #   render_to_remote "/cloud_model/guest/etc/shinken/services/#{check_name}.cfg", "#{build_dir}/etc/shinken/services/#{check_name}.cfg"
        # end
        # chroot! build_dir, "chown -R shinken:shinken /var/lib/shinken/libexec/", 'Failed to assign check scripts to shinken user'
      end
          
      def configure_system
        render_to_remote "/cloud_model/guest/etc/systemd/system/console-getty.service", "#{build_dir}/usr/lib/systemd/system/console-getty.service"

        render_to_remote "/cloud_model/guest/etc/systemd/system/network@.service", "#{build_dir}/etc/systemd/system/network@.service"
        chroot build_dir, "ln -s /usr/lib/systemd/system/network@.service /etc/systemd/system/multi-user.target.wants/network@eth0.service"
        
        render_to_remote "/cloud_model/guest/etc/systemd/system/cm_fix_permissions.service", "#{build_dir}/usr/lib/systemd/system/cm_fix_permissions.service"
        chroot build_dir, "ln -s /usr/lib/systemd/system/cm_fix_permissions.service /etc/systemd/system/multi-user.target.wants/"
      end
  
      def package_root
        build_tar '.', "/inst/guest.tar", one_file_system: true, exclude: [
          './etc/udev/rules.d/70-persistent-net.rules',
          './tmp/*',
          './run/*',
          './var/tmp/*',
          './var/run/*',
          './var/cache/*',
          './var/log/emerge*',
          './var/log/portage',
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
        @host.sftp.download! "/inst/guest.tar", "#{CloudModel.config.data_directory}/inst/guest.tar"
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
            ["Add CloudModel overlay", :config_layman],
            ["Update base packages", :emerge_update_world],
            ["Cleanup base system", :emerge_depclean],
            ["Cleanup gcc installation", :gcc_cleaner],
            ["Cleanup perl installation", :perl_cleaner],
            ["Cleanup python installation", :python_cleaner],
            ["Build system tools", :emerge_sys_tools],
            ["Build SSH", :emerge_ssh],
            ["Build ruby environment", :emerge_ruby],
            ["Build MongoDB server", :emerge_mongodb],
            ["Build Redis", :emerge_redis],
            ["Build Tomcat", :emerge_tomcat],
            ["Build Nginx with Passenger support", :build_nginx_passenger],
            ["Build Shinken", :emerge_shinken]
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
        
        true
      end
      
    end
  end
end