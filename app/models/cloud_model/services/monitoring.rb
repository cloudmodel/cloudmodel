module CloudModel
  module Services
    class Monitoring < Base
      field :graphite_web_enabled, type: Boolean, default: false
      
      def kind
        :monitoring
      end
      
      def components_needed
        [:shinken]
      end
      
      def port
        7767
      end
      
      def update_hosts_config! options={}
        worker = CloudModel::Services::MonitoringWorker.new self.guest, self
        worker.update_hosts_config options
        true
      end
    end
  end
end