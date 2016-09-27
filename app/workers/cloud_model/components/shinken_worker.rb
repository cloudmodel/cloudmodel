module CloudModel
  module Components
    class ShinkenWorker < BaseWorker
      def build build_path
        puts "        Install shinken and graphite-web"
        packages = %w(nagios-plugins)
        # packages = %w(shinken) # Shicken Base
        # packages += %w(shinken-mod-logstore-mongodb shinken-mod-mongodb shinken-mod-retention-mongodb) # Shinken MongoDB
        # packages += %w(shinken-mod-graphite shinken-mod-ui-graphite )
        packages += %w(mongodb-clients python-pycurl)
        packages += %w(graphite-carbon graphite-web) # Graphite/Carbon
        # packages += %w(shinken-mod-livestatus) # Livestatus
        packages += %w(python-pip git) # Use pip to install xmpp and shinken
        
        packages += %w(ruby-snmp ruby-mongo ruby-nokogiri ruby-redis) # Ruby deps for check scripts
        
        python_site_packages_path = '/usr/lib/python2.7/dist-packages'
        
        chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install shinken deps"
        chroot! build_path, "python2 /usr/bin/pip install git+https://github.com/ArchipelProject/xmpppy", 'Unable to install python graphite-web'
        #chroot! build_path, "python2 /usr/bin/pip install shinken --upgrade", "Failed to upgrade shinken"
        
        chroot! build_path, "useradd shinken", "Failed to add user shinken"
        chroot! build_path, "pip install --upgrade pip", "Failed to update pip"
        chroot! build_path, "pip install pymongo==2.7.2", "Failed to install pymongo 2.7.2"
        chroot! build_path, "pip install pycurl", "Failed to install pycurl"
        chroot! build_path, "pip install shinken==2.0.3 --install-option=\"--install-scripts=/usr/bin\"", "Failed to install shinken 2.0.3"       
        chroot! build_path, "shinken --init", "Failed to init shinken"
        
        %w(livestatus webui mongodb logstore-mongodb mod-mongodb retention-mongodb graphite ui-graphite auth-cfg-password).each do |service|
          chroot! build_path, "shinken install #{service}", "Failed to install shinken mod #{service}"
        end  
        
        puts "        Setup systemd startup files"
        render_to_remote "/cloud_model/guest/etc/tmpfiles.d/shinken.conf", "#{build_path}/etc/tmpfiles.d/shinken.conf"         
        %w(shinken-arbiter shinken-broker shinken-poller shinken-reactionner shinken-receiver shinken-scheduler).each do |service|
          render_to_remote "/cloud_model/guest/etc/systemd/system/#{service}.service", "#{build_path}/etc/systemd/system/#{service}.service"         
        end
        # disable shinken init.d start scripts
        @host.exec "rm #{build_path.shellescape}/etc/rc?.d/?01shinken*"
        @host.exec "rm #{build_path.shellescape}/etc/init.d/shinken*"  
      end
    end
  end
end