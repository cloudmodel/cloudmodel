module CloudModel
  module Components
    # Fleet device management server (osquery fleet manager) and its CLI
    # `fleetctl`, installed from the upstream release tarballs. Its database
    # comes from a {Services::Mysql} service in the same guest.
    class FleetComponent < BaseComponent
      def human_name
        "Fleet #{version}".strip
      end
    end
  end
end
