module CloudModel
  module Monitoring
    module Services
      class ForgejoRunnerChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
          do_check_for_errors_on data, {
            not_reachable: 'guest reachable',
            inactive: 'runner daemon active'
          }
        end
      end
    end
  end
end
