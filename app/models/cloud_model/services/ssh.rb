module CloudModel
  module Services
    # OpenSSH server service embedded in a {Guest}.
    #
    # SSH is typically the first service added to any guest. It is part of the
    # core OS image and requires no extra component installation. The service
    # health check performs a TCP ping on the configured port.
    class Ssh < Base
      # @!attribute [rw] port
      #   @return [Integer] SSH listen port (default: 22)
      field :port, type: Integer, default: 22

      # @!attribute [rw] authorized_keys
      #   @return [Array<String>, nil] raw public key strings to write to authorized_keys
      #     (deprecated — prefer SSH groups)
      field :authorized_keys, type: Array

      # TODO: Handle authorized_keys presets

      def kind
        :ssh
      end

      def components_needed
        super # ssh is default to core
      end

      def service_status
        t = Time.now
        if Net::Ping::TCP.new(guest.private_address, port).ping
          return {ping: Time.now - t}
        else
          return {key: :not_reachable, error: "Ping timeout", severity: :critical}
        end
      end
    end
  end
end