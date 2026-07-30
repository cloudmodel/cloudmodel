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

      # @!attribute [rw] jicofo_stats_port
      #   @return [Integer] Jicofo REST port exposing `/stats` health data
      #     (default: 8888). Internal port used only for monitoring, not a
      #     publicly exposed service port.
      field :jicofo_stats_port, type: Integer, default: 8888

      # @!attribute [rw] app_name
      #   @return [String] product name shown in the UI (interface_config `APP_NAME`)
      field :app_name, type: String, default: "Jitsi Meet"

      # @!attribute [rw] provider_name
      #   @return [String, nil] operator name shown in the UI (`PROVIDER_NAME`)
      field :provider_name, type: String, default: nil

      # @!attribute [rw] watermark_link
      #   @return [String, nil] URL the watermark logo links to (`JITSI_WATERMARK_LINK`)
      field :watermark_link, type: String, default: nil

      # @!attribute [rw] watermark_svg
      #   @return [String, nil] custom SVG watermark/logo markup overriding the default
      field :watermark_svg, type: String, default: nil

      # @!attribute [rw] default_background
      #   @return [String, nil] CSS color for the conference background
      #     (interface_config `DEFAULT_BACKGROUND`), e.g. `"rgb(0, 38, 50)"`
      field :default_background, type: String, default: nil

      # @!attribute [rw] welcome_page_url
      #   @return [String, nil] external URL the welcome page redirects to
      #     (config.js `welcomePage.customUrl`); nil keeps Jitsi's own page
      field :welcome_page_url, type: String, default: nil

      # @!attribute [rw] secure_domain
      #   @return [Boolean] "secure domain" setup: creating a room requires a
      #     registered XMPP user (prosody `internal_hashed` on the main vhost +
      #     jicofo XMPP authentication), while guests join running rooms
      #     anonymously via a `guest.<domain>` vhost
      field :secure_domain, type: Mongoid::Boolean, default: false

      # @!attribute [rw] admin_user
      #   @return [String, nil] XMPP user to provision on deploy (only with
      #     {#secure_domain}) — the account that may open rooms. Containers are
      #     rebuilt from the template on every redeploy, so the account is
      #     (re-)registered each deploy.
      field :admin_user, type: String, default: nil

      # @!attribute [rw] admin_password
      #   @return [String, nil] password for {#admin_user}
      field :admin_password, type: String, default: nil


      def kind
        :jitsi
      end

      # Jitsi serves WebRTC media (UDP/STUN/TURN) that must be reachable
      # directly by clients, so it may be exposed to public networks.
      def allow_public_service?
        true
      end

      def components_needed
        ([:jitsi] + super).uniq
      end

      def used_ports
        [[port, :udp], [videobridge_port, :tcp], [stun_port, :udp], [turn_port, :tcp]]
      end

      # Probe the Jitsi stack for monitoring. Jicofo (the conference focus) is
      # the source of truth: its REST `/stats` reports how many video bridges
      # are actually operational — the single best "can a conference be hosted?"
      # signal. The Videobridge's own HTTP port is additionally TCP-probed for
      # process liveness (its REST stats API is not exposed there). Returns a
      # data hash, or an error hash `{key:, error:, severity:}` consumed by
      # {CloudModel::Monitoring::Services::JitsiChecks}.
      def service_status
        status = {}

        status['videobridge_up'] =
          monitoring_tcp_open?(guest.private_address, videobridge_port) ? 1 : 0

        begin
          res = monitoring_http_get "http://#{guest.private_address}:#{jicofo_stats_port}/stats"
        rescue Exception => e
          return { key: :not_reachable,
                   error: "Jicofo REST unreachable on :#{jicofo_stats_port}: #{e.class}\n\n#{e}",
                   severity: :critical }
        end

        unless res.code == '200'
          return { key: :no_jicofo_stats,
                   error: "#{res.code}: Jicofo /stats unavailable", severity: :warning }
        end

        begin
          stats = JSON.parse res.body
        rescue Exception => e
          return { key: :parse_result, error: "#{e.class}\n\n#{e}", severity: :warning }
        end

        bridges = stats['bridge_selector'] || {}
        status['operational_bridges']       = bridges['operational_bridge_count']
        status['bridge_count']              = bridges['bridge_count']
        status['lost_bridges']              = bridges['lost_bridges']
        status['conferences']               = stats['conferences']
        status['participants']              = stats['participants']
        status['largest_conference']        = stats['largest_conference']
        status['total_conferences_created'] = stats['total_conferences_created']
        status['total_participants']        = stats['total_participants']
        status['ice_failed']                = stats.dig('participant_notifications', 'ice_failed')
        status['bridges_removed']           = stats.dig('bridge_failures', 'bridges_removed')
        status['threads']                   = stats['threads']
        status['version']                   = stats['version']
        status
      end

      private

      def monitoring_http_get url, timeout: 5
        uri = URI(url)
        Net::HTTP.start(uri.host, uri.port,
          open_timeout: timeout, read_timeout: timeout) do |http|
          http.request Net::HTTP::Get.new(uri.request_uri)
        end
      end

      def monitoring_tcp_open? host, port, timeout: 3
        Socket.tcp(host, port, connect_timeout: timeout) { true }
      rescue Exception
        false
      end

    end
  end
end