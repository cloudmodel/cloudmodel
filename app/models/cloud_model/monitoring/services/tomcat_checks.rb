module CloudModel
  module Monitoring
    module Services
      class TomcatChecks < CloudModel::Monitoring::Services::BaseChecks      
        def check
          do_check_for_errors_on data, {
            not_reachable: 'service reachable',
            no_tomcat_status: 'status available', 
            tomcat_status_forbidden: 'status forbidden', 
            parse_result: 'parse status'
          }
                
          do_check_value :mem_usage, data['memory_usage'], {
            warning: 80,
            critical: 90
          }
        
          do_check_value :thread_usage, data['thread_usage'], {
            warning: 80,
            critical: 90
          }
        end
      end
    end
  end
end