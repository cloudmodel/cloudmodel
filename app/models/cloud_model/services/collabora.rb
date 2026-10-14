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

      # Probe the Collabora Online server for monitoring. A healthy CODE server
      # serves the WOPI discovery document (what a Nextcloud/WOPI host needs to
      # talk to it) and reports its capabilities (whether document conversion
      # works). Returns a data hash, or an error hash `{key:, error:, severity:}`
      # consumed by {CloudModel::Monitoring::Services::CollaboraChecks}.
      def service_status
        base = "http://#{guest.private_address}:#{port}"
        status = {}

        begin
          discovery = monitoring_http_get "#{base}/hosting/discovery"
        rescue Exception => e
          return { key: :not_reachable, error: "#{e.class}\n\n#{e}", severity: :critical }
        end

        status['code'] = discovery.code.to_i
        unless discovery.code == '200'
          return { key: :no_discovery,
                   error: "#{discovery.code}: server up but /hosting/discovery not served",
                   severity: :warning }
        end

        # A 200 that is not a WOPI discovery document means CODE is misconfigured.
        status['discovery_ok'] = discovery.body.include?('<wopi-discovery>')

        # Capabilities expose whether the document-conversion engine is up. This
        # is a bonus signal, so never fail the whole check if it is unavailable.
        begin
          caps = JSON.parse monitoring_http_get("#{base}/hosting/capabilities").body
          status['convert_to']     = caps.dig('convert-to', 'available') ? 1 : 0
          status['mobile_support'] = caps['hasMobileSupport'] ? 1 : 0
        rescue Exception
          # ignore — discovery already established reachability
        end

        status
      end

    end
  end
end