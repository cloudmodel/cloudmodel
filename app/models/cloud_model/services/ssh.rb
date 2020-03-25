module CloudModel
  module Services
    class Ssh < Base
      field :port, type: Integer, default: 22
      field :authorized_keys, type: Array
      
      # TODO: Handle authorized_keys presets
      
      def kind
        :ssh
      end
      
      def components_needed
        [] # ssh is default to core
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