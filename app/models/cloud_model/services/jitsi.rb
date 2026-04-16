module CloudModel
  module Services
    # Jitsi Meet video-conferencing service embedded in a {Guest}.
    #
    # Deploys the Jitsi stack (Meet, Videobridge, Jicofo). Exposes four ports:
    # the main media UDP port, the Videobridge HTTP port, a STUN port, and a
    # TURN/TLS port. Service status is not actively probed (returns `{}`).
    class Jitsi < Base
      # @!attribute [rw] port
      #   @return [Integer] main media UDP port (default: 10000)
      field :port, type: Integer, default: 10000

      # @!attribute [rw] videobridge_port
      #   @return [Integer] Videobridge HTTP/colibri port (default: 9090)
      field :videobridge_port, type: Integer, default: 9090

      # @!attribute [rw] stun_port
      #   @return [Integer] STUN UDP port (default: 3478)
      field :stun_port, type: Integer, default: 3478

      # @!attribute [rw] turn_port
      #   @return [Integer] TURN/TLS TCP port (default: 5349)
      field :turn_port, type: Integer, default: 5349


      def kind
        :jitsi
      end

      def components_needed
        ([:jitsi] + super).uniq
      end

      def used_ports
        [[port, :udp], [videobridge_port, :tcp], [stun_port, :udp], [turn_port, :tcp]]
      end

      def service_status
        {}
      end

    end
  end
end