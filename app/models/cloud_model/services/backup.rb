module CloudModel
  module Services
    class Backup < Base
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