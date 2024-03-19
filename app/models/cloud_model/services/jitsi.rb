module CloudModel
  module Services
    class Jitsi < Base
      field :port, type: Integer, default: 10000
      field :videobridge_port, type: Integer, default: 9090
      field :stun_port, type: Integer, default: 3478
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