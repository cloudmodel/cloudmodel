module CloudModel
  module Monitoring
    module Services
      class SolrChecks < CloudModel::Monitoring::Services::BaseChecks
        def check
          do_check_for_errors_on data, {
            not_reachable: 'service reachable',
            no_solr_status: 'status available',
            solr_status_forbidden: 'status forbidden',
            parse_result: 'parse status'
          }

          do_check_value :mem_usage, data['memory_usage'], {
            critical: 90,
            warning: 80
          }
        end
      end
    end
  end
end