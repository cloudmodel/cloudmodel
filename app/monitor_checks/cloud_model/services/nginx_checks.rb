module CloudModel
  module Services
    class NginxChecks < CloudModel::Services::BaseChecks
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable', 
          no_nginx_status: 'status available', 
          ngnix_status_forbidden: 'status forbidden', 
          parse_result: 'parse status'
        }
      end
    end
  end
end