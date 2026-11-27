module CloudModel
  module Workers
    module Components
      # Component worker that installs Percona Server for MongoDB (a drop-in
      # replacement of the MongoDB Community server, same data files, same
      # `mongod` unit and `/etc/mongod.conf`) into a guest template chroot,
      # from Percona's apt repository of the minor line (see
      # {PerconaRepository}). The line is the component version, e.g.
      # `percona_server_mongodb@8.0` → repository `psmdb-80`.
      #
      # Unlike the MongoDB packages it runs as the `mongod` user (see
      # {Services::Mongodb#mongodb_user}).
      class PerconaServerMongodbComponentWorker < BaseComponentWorker
        def line
          @options[:component].try(:version).presence || "8.0"
        end

        def repository
          self.class.repository_for line
        end

        # @param line [String] e.g. `"8.0"`
        # @return [String] Percona repository of the line
        def self.repository_for line
          "psmdb-#{line.delete('.')}"
        end

        def build build_path
          PerconaRepository.add! self, build_path, @template, [repository]
          chroot! build_path, "DEBIAN_FRONTEND=noninteractive apt-get install percona-server-mongodb -y", "Failed to install Percona Server for MongoDB #{line}"
        end
      end
    end
  end
end
