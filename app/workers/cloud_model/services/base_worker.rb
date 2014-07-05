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
  
      def auto_start
        puts "        Add #{@model.class.model_name.human} to runlevel default"
        @host.exec "ln -sf /etc/systemd/system/#{@model.class.model_name.element.shellescape}.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
      end
      
    end
  end
end