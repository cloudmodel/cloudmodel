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
        @host.exec "ln -sf /etc/init.d/#{@model.class.model_name.element.shellescape} #{@guest.deploy_path.shellescape}/etc/runlevels/default/"
      end
      
    end
  end
end