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

      # SSH is key-authenticated and brute-force rate-limited, so it may be
      # exposed to public networks.
      def allow_public_service?
        true
      end

      def components_needed
        super # ssh is default to core
      end

      # Reachability of the SSH port: a TCP connect with a timeout, no
      # third-party ping library (net-ping pulls in cap2, which needs the
      # libcap headers on every host application).
      def service_status
        t = Time.now
        Socket.tcp(guest.private_address, port, connect_timeout: PING_TIMEOUT) { }
        {ping: Time.now - t}
      rescue SystemCallError, SocketError, IO::TimeoutError => e
        {key: :not_reachable, error: "Ping timeout (#{e.class})", severity: :critical}
      end

      PING_TIMEOUT = 5
    end
  end
end