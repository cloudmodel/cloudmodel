# Needs nginx(incl. ruby) and mongodb services
module CloudModel
  module Services
    class MonitoringWorker < CloudModel::Services::BaseWorker
      def write_hosts_config options = {}
        puts "        Write shinken hosts#{options[:title]}"
        
        hosts_dir = options[:hosts_dir] || "#{@guest.deploy_path}/etc/shinken/hosts"
        mkdir_p "#{hosts_dir}"

        CloudModel::Host.all.each do |host|
          render_to_remote "/cloud_model/guest/etc/shinken/hosts/host.cfg", "#{hosts_dir}/#{host.name}.cfg", host: host
          
          host.guests.each do |guest|
            render_to_remote "/cloud_model/guest/etc/shinken/hosts/guest.cfg", "#{hosts_dir}/#{host.name}.#{guest.name}.cfg", guest: guest
          end
        end
      end
      
      def update_hosts_config options={}
        ts = Time.now.strftime('%Y%m%d%M%H%S')
        hosts_base_path = "/etc/shinken/hosts"
        hosts_build_path = "#{hosts_base_path}.build.#{ts}"
        hosts_old_path = "#{hosts_base_path}.old.#{ts}"
        
        build_dir = guest.base_path
        
        write_hosts_config hosts_dir: "#{build_dir}#{hosts_build_path}", title: " for #{guest.name}"
        chroot build_dir, "mv /etc/shinken/hosts #{hosts_old_path}"
        chroot! build_dir, "mv #{hosts_build_path} /etc/shinken/hosts", 'Unable to move hosts config'
      end
      
      def write_config
        #plugins_dir = '/usr/lib/nagios/plugins'
        plugins_dir = '/var/lib/shinken/libexec'
        
        write_hosts_config
           
        puts "        Write shinken config"
        #render_to_remote "/cloud_model/guest/etc/shinken/arbiters/arbiter-master.cfg", "#{@guest.deploy_path}/etc/shinken/arbiters/arbiter-master.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/brokers/broker-master.cfg", "#{@guest.deploy_path}/etc/shinken/brokers/broker-master.cfg", service: @model
        #render_to_remote "/cloud_model/guest/etc/shinken/schedulers/scheduler-master.cfg", "#{@guest.deploy_path}/etc/shinken/schedulers/scheduler-master.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/livestatus.cfg", "#{@guest.deploy_path}/etc/shinken/modules/livestatus.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/webui.cfg", "#{@guest.deploy_path}/etc/shinken/modules/webui.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/ui-graphite.cfg", "#{@guest.deploy_path}/etc/shinken/modules/ui-graphite.cfg", service: @model
          
        mkdir_p "#{@guest.deploy_path}/etc/graphite"  
        render_to_remote "/cloud_model/guest/etc/graphite/carbon.conf", "#{@guest.deploy_path}/etc/graphite/carbon.conf", 0544
        render_to_remote "/cloud_model/guest/etc/graphite/storage-schemas.conf", "#{@guest.deploy_path}/etc/graphite/storage-schemas.conf", 0544
                          
        mkdir_p "#{@guest.deploy_path}/etc/shinken/commands"
        mkdir_p "#{@guest.deploy_path}/etc/shinken/contacts"
        mkdir_p "#{@guest.deploy_path}/etc/shinken/contactgroups"
        mkdir_p "#{@guest.deploy_path}/etc/shinken/notificationways"
        mkdir_p "#{@guest.deploy_path}/etc/shinken/services"
        mkdir_p plugins_dir

        puts "        Write notification config"        
        render_to_remote "/cloud_model/guest/etc/shinken/contactgroups/admin.cfg", "#{@guest.deploy_path}/etc/shinken/contactgroups/admins.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/contacts/admin.cfg", "#{@guest.deploy_path}/etc/shinken/contacts/admin.cfg", service: @model
        
        if CloudModel.config.uses_xmpp?
          render_to_remote "/cloud_model/guest/etc/shinken/contacts/xmpp.cfg", "#{@guest.deploy_path}/etc/shinken/contacts/xmpp.cfg", service: @model
          render_to_remote "/cloud_model/guest/etc/shinken/notificationways/xmpp.cfg", "#{@guest.deploy_path}/etc/shinken/notificationways/xmpp.cfg", service: @model
          #render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/notify_by_xmpp.py", "#{@guest.deploy_path}#{plugins_dir}/notify_by_xmpp.py", 0700
          render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/notify_by_xmpp.ini", "#{@guest.deploy_path}#{plugins_dir}/notify_by_xmpp.ini", 0600
        end
            
        puts "        Write nginx config for graphite"
        mkdir_p "#{@guest.deploy_path}/etc/nginx/server.d"
        mkdir_p "#{@guest.deploy_path}/usr/lib/python2.7/dist-packages/graphite/public"
        render_to_remote "/cloud_model/guest/etc/nginx/server.d/graphite.conf", "#{@guest.deploy_path}/etc/nginx/server.d/graphite.conf", service: @model         
        render_to_remote "/cloud_model/guest/graphite/passenger_wsgi.py", "#{@guest.deploy_path}/usr/lib/python2.7/dist-packages/graphite/passenger_wsgi.py", 0755, service: @model         
           
        render_to_remote "/cloud_model/guest/etc/shinken/shinken.cfg", "#{@guest.deploy_path}/etc/shinken/shinken.cfg"

        %w(shinken_helpers check_mk_helpers).each do |file_name|
          render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/#{file_name}.rb", "#{@guest.deploy_path}#{plugins_dir}/#{file_name}.rb", 0700
        end
        %w(https).each do |check_name|
          render_to_remote "/cloud_model/guest/etc/shinken/commands/check_#{check_name}.cfg", "#{@guest.deploy_path}/etc/shinken/commands/check_#{check_name}.cfg"
          render_to_remote "/cloud_model/guest/etc/shinken/services/#{check_name}.cfg", "#{@guest.deploy_path}/etc/shinken/services/#{check_name}.cfg"
        end
        
        %w(cpu disks mem net_usage lm_sensors lvm mdstat mongodb smart cgroup_cpu cgroup_mem nginx redis tomcat).each do |check_name|
          render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/check_#{check_name}.rb", "#{@guest.deploy_path}#{plugins_dir}/check_#{check_name}.rb", 0700
          render_to_remote "/cloud_model/guest/etc/shinken/commands/check_#{check_name}.cfg", "#{@guest.deploy_path}/etc/shinken/commands/check_#{check_name}.cfg"
          render_to_remote "/cloud_model/guest/etc/shinken/services/#{check_name}.cfg", "#{@guest.deploy_path}/etc/shinken/services/#{check_name}.cfg"
        end

        # Shinken delivers an old version of check_mongodb.py - so we use our own version
        
        render_to_remote "/cloud_model/guest/var/lib/shinken/libexec/check_mongodb.py", "#{@guest.deploy_path}#{plugins_dir}/check_mongodb.py", 0700      

        chroot! @guest.deploy_path, "chown -R shinken:shinken #{plugins_dir}", 'Failed to assign check scripts to shinken user' 
      end
      
      def auto_start
        puts "        Add Monitoring Services to runlevel default"
        
        puts "        Write graphite-web systemd"
        mkdir_p "#{@guest.deploy_path}/etc/systemd/system/nginx.service.d"
        render_to_remote "/cloud_model/guest/etc/systemd/system/nginx.service.d/graphite-web.conf", "#{@guest.deploy_path}/etc/systemd/system/nginx.service.d/graphite-web.conf"        
        
        %w(carbon-cache shinken-arbiter shinken-broker shinken-poller shinken-reactionner shinken-receiver shinken-scheduler).each do |service|
          @host.exec "ln -sf /lib/systemd/system/#{service}.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
        end
        
        # remove example host
        @host.exec "rm #{@guest.deploy_path.shellescape}/etc/shinken/hosts/localhost.cfg"
      
        # TODO: Resolve dependencies
        # Services::Nginx.new(@host, @options).write_config
        # Services::Mongodb.new(@host, @options).write_config    
      end
    end
  end
end


