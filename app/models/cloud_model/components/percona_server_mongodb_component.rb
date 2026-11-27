module CloudModel
  module Components
    # Percona Server for MongoDB (SSPL, drop-in replacement of the MongoDB
    # Community server) from Percona's own apt repository. The version is the
    # minor line, e.g. `percona_server_mongodb@8.0`.
    class PerconaServerMongodbComponent < BaseComponent
      def human_name
        "Percona Server for MongoDB #{version}".strip
      end
    end
  end
end
