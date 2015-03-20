module CloudModel
  module Services
    class MonitoringWorker < CloudModel::Services::BaseWorker
      def write_hosts_config options = {}
        puts "        Write shinken hosts"
        
        hosts_dir = options[:hosts_dir] || "#{@guest.deploy_path}/etc/shinken/hosts"
        mkdir_p "#{hosts_dir}"

        CloudModel::Host.all.each do |host|
          render_to_remote "/cloud_model/guest/etc/shinken/hosts/host.cfg", "#{hosts_dir}/#{host.name}.cfg", host: host
          
          host.guests.each do |guest|
            render_to_remote "/cloud_model/guest/etc/shinken/hosts/guest.cfg", "#{hosts_dir}/#{host.name}.#{guest.name}.cfg", guest: guest
          end
        end
      end
      
      def update_hosts_config
        ts = Time.now.strftime('%Y%m%d%M%H%S')
        hosts_base_path = "/etc/shinken/hosts"
        hosts_build_path = "#{hosts_base_path}.build.#{ts}"
        hosts_old_path = "#{hosts_base_path}.old.#{ts}"
        
        build_dir = guest.base_path
        
        write_hosts_config hosts_dir: "#{build_dir}#{hosts_build_path}"
        chroot! build_dir, "mv /etc/shinken/hosts #{hosts_old_path} && mv #{hosts_build_path} /etc/shinken/hosts"
        # TODO: run on guest: " && systemctl restart shinken-arbiter", "Failed to restart shinken"
      end
      
      def write_config
        write_hosts_config
           
        puts "        Write shinken config"
        render_to_remote "/cloud_model/guest/etc/shinken/brokers/broker-master.cfg", "#{@guest.deploy_path}/etc/shinken/brokers/broker-master.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/livestatus.cfg", "#{@guest.deploy_path}/etc/shinken/modules/livestatus.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/webui.cfg", "#{@guest.deploy_path}/etc/shinken/modules/webui.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/ui-graphite.cfg", "#{@guest.deploy_path}/etc/shinken/modules/ui-graphite.cfg", service: @model
          
        puts "        Write notification config"  
        render_to_remote "/cloud_model/guest/etc/shinken/contactgroups/admin.cfg", "#{@guest.deploy_path}/etc/shinken/contactgroups/admins.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/contacts/admin.cfg", "#{@guest.deploy_path}/etc/shinken/contacts/admin.cfg", service: @model
        
        if CloudModel.config.uses_xmpp
          render_to_remote "/cloud_model/guest/etc/shinken/contacts/xmpp.cfg", "#{@guest.deploy_path}/etc/shinken/contacts/xmpp.cfg", service: @model
          render_to_remote "/cloud_model/guest/etc/shinken/notificationways/xmpp.cfg", "#{@guest.deploy_path}/etc/shinken/notificationways/xmpp.cfg", service: @model
          host.exec! "sed -i s,#!/usr/bin/python\\ ,#!/usr/bin/python2\\ , #{@guest.deploy_path}/var/lib/shinken/libexec/notify_by_xmpp.py", 'Failed to patch xmpp notify'
          render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/notify_by_xmpp.ini", "#{@guest.deploy_path}/var/lib/shinken/libexec/notify_by_xmpp.ini", 0600
        end
            
        puts "        Write nginx config for graphite"
        mkdir_p "#{@guest.deploy_path}/etc/nginx/server.d"
        render_to_remote "/cloud_model/guest/etc/nginx/server.d/graphite.conf", "#{@guest.deploy_path}/etc/nginx/server.d/graphite.conf", service: @model         
               
        puts "        Fix systemd services"
        host.exec! "for i in #{@guest.deploy_path}/usr/lib/systemd/system/shinken-*; do sed -i s,/usr/sbin,/usr/bin, $i; done", 'Failed to patch shinken services'
      
        # TODO: Remove this lines once it is in image
        build_dir = @guest.deploy_path
        render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/snmp_helpers.rb", "#{build_dir}/var/lib/shinken/libexec/snmp_helpers.rb", 0700
        %w(cpu disks mem net_usage lm_sensors lvm mdstat smart guest_cpu guest_mem mongodb nginx redis tomcat).each do |check_name|
          render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/check_#{check_name}.rb", "#{build_dir}/var/lib/shinken/libexec/check_#{check_name}.rb", 0700
          render_to_remote "/cloud_model/guest/etc/shinken/commands/check_#{check_name}.cfg", "#{build_dir}/etc/shinken/commands/check_#{check_name}.cfg"
          render_to_remote "/cloud_model/guest/etc/shinken/services/#{check_name}.cfg", "#{build_dir}/etc/shinken/services/#{check_name}.cfg"
        end
        chroot! build_dir, "chown -R shinken:shinken /var/lib/shinken/libexec/", 'Failed to assign check scripts to shinken user'
        chroot build_dir, "rm /var/lib/shinken/libexec/check_sensors.rb /etc/shinken/commands/check_sensors.cfg /etc/shinken/services/sensors.cfg"
      end
    
      def auto_start
        puts "        Add Monitoring Services to runlevel default"
        
        %w(carbon-cache graphite-web shinken-arbiter shinken-broker shinken-poller shinken-reactionner shinken-receiver shinken-scheduler).each do |service|
          @host.exec "ln -sf /usr/lib/systemd/system/#{service}.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
        end
      
        # TODO: Resolve dependencies
        # Services::Nginx.new(@host, @options).write_config
        # Services::Mongodb.new(@host, @options).write_config    
      end
    end
  end
end


