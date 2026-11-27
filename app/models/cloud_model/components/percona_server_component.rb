module CloudModel
  module Components
    # Percona Server for MySQL (GPL, MySQL compatible) from Percona's own apt
    # repository. The version is the release series, e.g. `percona_server@8.4`.
    class PerconaServerComponent < BaseComponent
      def human_name
        "Percona Server #{version}".strip
      end
    end
  end
end
