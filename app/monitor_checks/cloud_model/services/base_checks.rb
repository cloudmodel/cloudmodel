module CloudModel
  module Services
    class BaseChecks < ::CloudModel::BaseChecks
      def initialize host, guest, service, options = {}      
        @indent = 4
        @host = host
        @guest = guest
        @subject = service

        @result = @subject.service_status

        store_check_result
      end
      
      def get_result
      end
    
      def check
      
      end
    end
  end
end