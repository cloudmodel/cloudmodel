module CloudModel
  module Monitoring
    module Services
      class CollaboraChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
          do_check_for_errors_on data, {
            not_reachable: 'service reachable',
            no_discovery:  'WOPI discovery available'
          }

          # Document conversion is a core feature; if the engine is down the
          # server answers but cannot actually do useful work.
          if data.is_a?(Hash) && data.key?('convert_to')
            do_check :collabora_convert_to, 'document conversion available', {
              warning: data['convert_to'] != 1
            }, message: 'Collabora convert-to (document conversion) engine unavailable'
          end
        end
      end
    end
  end
end
