module CloudModel
  module Workers
    module Components
      class Neo4jComponentWorker < BaseComponentWorker
        def _prepare_collabora_repository build_path
          chroot! build_path, "apt-get install dirmngr gnupg -y", "Failed to install key management"
          chroot! build_path, "echo 'deb https://debian.neo4j.com stable 4.1' | sudo tee /etc/apt/sources.list.d/neo4j.list", "Failed to add neo4j to list if repos"
          chroot! build_path, "wget -q -O - https://debian.neo4j.com/neotechnology.gpg.key | sudo apt-key add - ", "Failed to add neo4j key"
        end


        def build build_path
          ### TODO; Test build in collabora
          ### if running: remove /cloud_model/guest/etc/apt/sources.list.d/collabora.list
          ### if not running: fix sources
          _prepare_collabora_repository build_path

          chroot! build_path, "apt-get update", "Failed to update packages"
          chroot! build_path, "apt-get install neo4j -y", "Failed to install neo4j"
        end
      end
    end
  end
end
