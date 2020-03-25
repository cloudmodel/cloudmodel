require 'net/ping'

module CloudModel
  module Services
    class SshChecks < CloudModel::Services::BaseChecks      
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable'
        }
      end
    end
  end
end