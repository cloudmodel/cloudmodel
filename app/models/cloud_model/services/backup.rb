module CloudModel
  module Services
    # Headless backup coordination service embedded in a {Guest}.
    #
    # This service installs the Ruby runtime and acts as the execution context
    # for backup scripts running inside the guest. It has no network port and
    # no live health check. Actual data backup is handled by individual
    # services with `has_backups: true` and by {LxdCustomVolume}s.
    class Backup < Base
      def kind
        :headless
      end

      def components_needed
        ([:ruby] + super).uniq
      end

      def service_status
        false
      end
    end
  end
end