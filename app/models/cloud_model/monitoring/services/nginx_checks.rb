module CloudModel
  module Monitoring
    module Services
      class NginxChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
          do_check_for_errors_on data, {
            not_reachable: 'service reachable', 
            no_nginx_status: 'status available', 
            ngnix_status_forbidden: 'status forbidden', 
            parse_result: 'parse status'
          }
        end
      end
    end
  end
end