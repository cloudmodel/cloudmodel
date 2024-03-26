module CloudModel
  module Services
    class Forgejo < Base
      field :port, type: Integer, default: 3000
      field :default_theme, type: String, default: "forgejo-auto"
      field :logo_svg, type: String, default: nil

      field :secret_key, type: String, default: nil
      field :internal_token, type: String, default: nil
      field :lfs_jwt_secret, type: String, default: nil
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