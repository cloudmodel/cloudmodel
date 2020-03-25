module CloudModel
  module Services
    class BaseChecks < ::CloudModel::BaseChecks
      def initialize host, guest, service, options = {}      
        @indent = 4
        @host = host
        @guest = guest
        @subject = service

        if options[:cached]
          @result = @subject.monitoring_last_check_result
        else
          print "      * Acqire data ..."
          @result = @subject.service_status
          puts "[Done]"
      
          store_check_result
        end
      end
      
      def get_result
      end
    
      def check
      
      end
    end
  end
end