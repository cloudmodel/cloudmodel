module CloudModel
  module Monitoring
    module Services
      class BaseChecks < ::CloudModel::Monitoring::BaseChecks        
        def aquire_data
          @subject.service_status
        end
        
        def indent_size
          4
        end
    
        def check
      
        end
      end
    end
  end
end