module CloudModel
  module Services
    class Phpfpm < Base
      field :port, type: Integer, default: 9000
      field :php_components, type: Array, default: []
      field :php_upload_max_filesize, type: Integer, default: 2 # Size in M

      def kind
        :phpfpm
      end

      def php_components= components
        self[:php_components] = components.map(&:to_sym) & available_php_components
      end

      def components_needed
        [:php] + php_components.map(&:to_sym)
      end

      def available_php_components
        [:php_mysql, :php_imagemagick, :php_imap]
      end

      def service_status
        begin
          result = `SCRIPT_NAME=/fpm_status SCRIPT_FILENAME=/fpm_status QUERY_STRING=full\\&json REQUEST_METHOD=GET cgi-fcgi -bind -connect #{guest.private_address}:#{port}`
        rescue Exception => e
          return {key: :not_reachable, error: "Failed to get fcgi status\n#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

        begin
          json = JSON.parse result.lines.last
        rescue
          return {key: :parse_phpfpm_result, error: "#{e.class}\n\n#{e.to_s}\n--\n#{result}", severity: :warning}
        end
      end
    end
  end
end