module CloudModel
  module Monitoring
    module Services
      class BaseChecks < ::CloudModel::Monitoring::BaseChecks
        def acquire_data
          @subject.service_status
        end

        def indent_size
          4
        end

        def line_prefix
          "[#{@subject.guest.host.name}] #{super}"
        end

        # Records every numeric counter the service status exposes (connections,
        # requests, memory, cache hits, …) so they can be graphed over time.
        def sample_metrics
          flatten_numeric data
        end

        def check

        end
      end
    end
  end
end