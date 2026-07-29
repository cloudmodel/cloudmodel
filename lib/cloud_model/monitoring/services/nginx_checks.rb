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
              fatal: Time.now,
              critical: Time.now + 1.week,
              warning: Time.now + 1.month
            }
          end
        end

        def sample_metrics
          return {} unless data.is_a? Hash
          metrics = {}

          metrics['http.active_connections'] = data['active'].to_f if data['active']
          %w(reading writing waiting).each do |state|
            metrics["http.#{state}"] = data[state].to_f if data[state]
          end

          if timing = data['timing']
            metrics['http.rps'] = timing['rps']
            metrics['http.rate_4xx'] = timing['rate_4xx']
            metrics['http.rate_5xx'] = timing['rate_5xx']
            (timing['request_ms'] || {}).each do |agg, value|
              metrics["http.req_#{agg}_ms"] = value
            end
            (timing['upstream_ms'] || {}).each do |agg, value|
              metrics["http.upstream_#{agg}_ms"] = value
            end
          end

          if passenger = data['passenger']
            processes = 0
            queue = 0
            (passenger['supergroups'] || []).each do |supergroup|
              group = supergroup['group'] || {}
              processes += Array(group['processes']).size
              queue += group['get_wait_list_size'].to_i
            end
            queue += passenger['get_wait_list_size'].to_i
            metrics['passenger.processes'] = processes.to_f
            metrics['passenger.queue'] = queue.to_f
          end

          metrics.compact
        end
      end
    end
  end
end