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

          if data['ssl_cert'] and data['ssl_cert']['not_after']
            do_check_value :cert_valid_before, data['ssl_cert']['not_before'].to_time, {
              fatal: Time.now
            }

            do_check_above_value :cert_valid_after, data['ssl_cert']['not_after'].to_time, {
              warning: Time.now + 1.month,
              critical: Time.now + 1.week,
              fatal: Time.now
            }
          end
        end
      end
    end
  end
end