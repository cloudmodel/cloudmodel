module CloudModel
  module Monitoring
    module Services
      class ForgejoChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
          do_check_for_errors_on data, {
            not_reachable: 'service reachable',
            not_found: 'metrics available',
            not_parsable: 'parse metrics'
          }
        end
      end
    end
  end
end
