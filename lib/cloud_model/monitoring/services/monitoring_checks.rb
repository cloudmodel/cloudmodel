module CloudModel
  module Monitoring
    module Services
      # The headless Monitoring service is the agent that produces the check
      # data itself — if it were not running, no data would arrive and the
      # host/guest checks would already flag staleness. This class exists to
      # satisfy the per-service check lookup (resolving the historical :no_check
      # info issue); it has no dedicated probe of its own.
      class MonitoringChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
        end
      end
    end
  end
end
