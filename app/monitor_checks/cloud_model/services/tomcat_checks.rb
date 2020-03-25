module CloudModel
  module Services
    class SolrChecks < CloudModel::Services::BaseChecks      
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable',
          no_tomcat_status: 'status available', 
          tomcat_status_forbidden: 'status forbidden', 
          parse_result: 'parse status'
        }
                
        do_check_value :mem_usage, @result['memory_usage'], {
          warning: 80,
          critical: 90
        }
        
        do_check_value :thread_usage, @result['thread_usage'], {
          warning: 80,
          critical: 90
        }
      end
    end
  end
end

