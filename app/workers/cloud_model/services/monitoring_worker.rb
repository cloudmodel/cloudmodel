module CloudModel
  module Services
    class MonitoringWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Write shinken hosts"
        CloudModel::Host.all.each do |host|
          render_to_remote "/cloud_model/guest/etc/shinken/hosts/host.cfg", "#{@guest.deploy_path}/etc/shinken/hosts/#{host.name}.cfg", host: host
          
          host.guests.each do |guest|
            render_to_remote "/cloud_model/guest/etc/shinken/hosts/guest.cfg", "#{@guest.deploy_path}/etc/shinken/hosts/#{host.name}.#{guest.name}.cfg", guest: guest
          end
        end
           
        puts "        Write shinken config"
        render_to_remote "/cloud_model/guest/etc/shinken/brokers/broker-master.cfg", "#{@guest.deploy_path}/etc/shinken/brokers/broker-master.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/livestatus.cfg", "#{@guest.deploy_path}/etc/shinken/modules/livestatus.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/webui.cfg", "#{@guest.deploy_path}/etc/shinken/modules/webui.cfg", service: @model
        render_to_remote "/cloud_model/guest/etc/shinken/modules/ui-graphite.cfg", "#{@guest.deploy_path}/etc/shinken/modules/ui-graphite.cfg", service: @model
            
        puts "        Write nginx config for graphite"
        mkdir_p "#{@guest.deploy_path}/etc/nginx/server.d"
        render_to_remote "/cloud_model/guest/etc/nginx/server.d/graphite.conf", "#{@guest.deploy_path}/etc/nginx/server.d/graphite.conf", service: @model         
               
        puts "        Fix systemd services"
        host.exec! "for i in #{@guest.deploy_path}/usr/lib/systemd/system/shinken-*; do sed -i s,/usr/sbin,/usr/bin, $i; done", 'Failed to patch shinken services'
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


