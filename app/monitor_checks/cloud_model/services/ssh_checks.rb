require 'net/ping'

module CloudModel
  module Services
    class SshChecks < CloudModel::Services::BaseChecks      
      def get_result
        t = Time.now
        if Net::Ping::TCP.new(@guest.private_address, @subject.port).ping
          return {ping: Time.now - t}
        else
          return {key: :not_reachable, error: "Ping timeout", severity: :critical}
        end
      end
      
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable'
        }
      end
    end
  end
end