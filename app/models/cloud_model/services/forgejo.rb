module CloudModel
  module Services
    # Forgejo self-hosted Git service embedded in a {Guest}.
    #
    # Deploys a Forgejo instance (a lightweight Gitea fork) for Git repository
    # hosting. Health status is derived from the Prometheus metrics endpoint at
    # `/metrics`. All secret material (secret key, tokens, JWT secrets) is
    # stored as model fields and rendered into the Forgejo configuration at
    # deploy time.
    class Forgejo < Base
      # @!attribute [rw] port
      #   @return [Integer] Forgejo HTTP port (default: 3000)
      field :port, type: Integer, default: 3000

      # @!attribute [rw] default_theme
      #   @return [String] Forgejo UI theme name (default: `"forgejo-auto"`)
      field :default_theme, type: String, default: "forgejo-auto"

      # @!attribute [rw] logo_svg
      #   @return [String, nil] custom SVG logo markup to override the default Forgejo logo
      field :logo_svg, type: String, default: nil

      # @!attribute [rw] secret_key
      #   @return [String, nil] global secret key for CSRF and session signing
      field :secret_key, type: String, default: nil

      # @!attribute [rw] internal_token
      #   @return [String, nil] JWT token for internal API calls between Forgejo components
      field :internal_token, type: String, default: nil

      # @!attribute [rw] lfs_jwt_secret
      #   @return [String, nil] secret used to sign Git LFS JWT tokens
      field :lfs_jwt_secret, type: String, default: nil

      # @!attribute [rw] oauth_jwt_secret
      #   @return [String, nil] secret used to sign OAuth2 JWT tokens
      field :oauth_jwt_secret, type: String, default: nil

      def kind
        :forgejo
      end

      def components_needed
        ([:forgejo] + super).uniq
      end

      def used_ports
        [[port, :tcp]]
      end

      def service_status
        uri = URI("http://#{guest.private_address}:#{port}/metrics")

        data = {}

        begin
          res = nil

          Net::HTTP.start(uri.host, uri.port,
            :use_ssl => uri.scheme == 'https',
            :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

            req = Net::HTTP::Get.new uri.request_uri

            res = http.request req
          end
        rescue Exception => e
           return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

        if res.code == '404'
          return {key: :not_found, error: "Metrics not found, but server answering", severity: :warning}
        end

        begin
          res.body.lines.each do |line|
            if line =~ /^\#/
            else
              key, value = line.split(' ')
              data[key] = value
            end
          end
        rescue Exception => e
          {key: :not_parsable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

        data
      end
    end
  end
end