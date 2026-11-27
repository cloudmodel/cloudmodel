module CloudModel
  module Monitoring
    module Services
      class FleetChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
          do_check_for_errors_on data, {
            not_reachable: 'service reachable',
            not_healthy: 'service healthy'
          }
        end
      end
    end
  end
end
