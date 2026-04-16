module CloudModel
  module Services
    # Headless monitoring agent service embedded in a {Guest}.
    #
    # Installs the check_mk agent and supporting components (Ruby, libfcgi,
    # MariaDB client) so that the guest can report metrics back to the
    # CloudModel monitoring system. The service has no exposed port and no
    # live health check of its own.
    class Monitoring < Base
      # @!attribute [rw] graphite_web_enabled
      #   @return [Boolean] whether to expose a Graphite web UI on this guest
      field :graphite_web_enabled, type: Mongoid::Boolean, default: false

      def kind
        :headless
      end

      def components_needed
        ([:ruby, :libfcgi, :mariadb_client] + super).uniq
      end

      def service_status
        false
      end
    end
  end
end