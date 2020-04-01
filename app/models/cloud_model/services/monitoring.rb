module CloudModel
  module Services
    class Monitoring < Base
      field :graphite_web_enabled, type: Mongoid::Boolean, default: false
      
      def kind
        :headless
      end
      
      def components_needed
        [:ruby]
      end
      
      def service_status
        false
      end
    end
  end
end