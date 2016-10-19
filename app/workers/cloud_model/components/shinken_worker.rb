module CloudModel
  module Components
    class ShinkenWorker < BaseWorker
      def build build_path
        puts "        Install shinken and graphite-web"
        packages = %w(nagios-plugins)
        packages += %w(mongodb-clients python-pycurl python-sqlite python-cherrypy3)
        packages += %w(graphite-carbon graphite-web) # Graphite/Carbon
        packages += %w(python-pip git) # Use pip to install xmpp and shinken
        
        packages += %w(ruby-snmp ruby-mongo ruby-nokogiri ruby-redis) # Ruby deps for check scripts
        
        python_site_packages_path = '/usr/lib/python2.7/dist-packages'
        
        chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install shinken deps"
        chroot! build_path, "python2 /usr/bin/pip install git+https://github.com/ArchipelProject/xmpppy", 'Unable to install python graphite-web'
        
        chroot! build_path, "useradd shinken", "Failed to add user shinken"
        chroot! build_path, "pip install --upgrade pip", "Failed to update pip"
        [
          "pymongo>=3.0.3",
          "requests",
          "arrow",
          "bottle==0.12.8",
          "pycurl",
          "passlib",
        ].each do |pip_package|
          chroot! build_path, "pip install #{pip_package}", "Failed to install #{pip_package}"
        end
        
        chroot! build_path, "pip install shinken --install-option=\"--install-scripts=/usr/bin\"", "Failed to install shinken"       
        chroot! build_path, "shinken --init", "Failed to init shinken"
        
        %w(http ssh livestatus webui2 logstore-mongodb mod-mongodb retention-mongodb graphite2 ui-graphite2 auth-cfg-password named-pipe).each do |service|
          chroot! build_path, "shinken install #{service}", "Failed to install shinken mod #{service}"
        end
        
        chroot! build_path, "chmod u+s /usr/lib/nagios/plugins/check_icmp", "Failed to suid check_icmp"
        
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