require 'redis'

module CloudModel
  module Monitoring
    module Services
      class RedisChecks < CloudModel::Monitoring::Services::BaseChecks      
        def check
          do_check_for_errors_on @result, {
            not_reachable: 'service reachable'
          }
        end
      end
    end
  end
end