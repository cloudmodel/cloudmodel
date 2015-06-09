module CloudModel
  module Services
    class BaseWorker  < CloudModel::BaseWorker
  
      def initialize guest, model
        @guest = guest
        @host = @guest.host
        @model = model
      end
      
      def guest
        @guest
      end
      
      def host
        @host
      end
  
      def write_config
      end
  
      def service_name
        @model.class.model_name.element.shellescape
      end
  
      def overlay_path 
        "#{@guest.deploy_path.shellescape}/etc/systemd/system/#{service_name}.service.d"
      end
  
      def auto_restart
        false
      end
  
      def auto_start
        puts "        Add #{@model.class.model_name.human} to runlevel default"
        @host.exec "ln -sf /lib/systemd/system/#{service_name}.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
        if auto_restart
          mkdir_p overlay_path
          render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{overlay_path}/restart.conf"
        end
      end
      
    end
  end
end