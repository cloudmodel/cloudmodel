module CloudModel
  module Monitoring
    module Services
      class MongodbChecks < CloudModel::Monitoring::Services::BaseChecks  
        def check
          do_check_for_errors_on data, {
            not_reachable: 'service reachable'
          }
        end
      end
    end
  end
end