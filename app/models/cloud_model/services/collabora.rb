module CloudModel
  module Services
    # Collabora Online office suite service embedded in a {Guest}.
    #
    # Runs the Collabora Online Development Edition (CODE) server, providing
    # browser-based document editing via the WOPI protocol. Typically paired
    # with a Nextcloud or similar host that acts as the WOPI host.
    class Collabora < Base
      # @!attribute [rw] port
      #   @return [Integer] Collabora HTTP port (default: 9980)
      field :port, type: Integer, default: 9980

      # @!attribute [rw] wopi_host
      #   @return [String, nil] hostname of the WOPI client (e.g. Nextcloud instance)
      #     that is allowed to connect to this Collabora server
      field :wopi_host, type: String, default: nil

      def kind
        :collabora
      end

      def components_needed
        ([:collabora] + super).uniq
      end

      def service_status
        {}
      end

    end
  end
end