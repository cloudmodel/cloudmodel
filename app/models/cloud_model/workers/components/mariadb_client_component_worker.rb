module CloudModel
  module Workers
    module Components
      class MariadbClientComponentWorker < BaseComponentWorker
        def build build_path
          # Use latest mariadb instead of Ubunu's one
          chroot! build_path, "apt-get install curl -y", "Failed to install curl"
          chroot! build_path, "curl -sS https://downloads.mariadb.com/MariaDB/mariadb_repo_setup | bash", "Failed to setup mariadb repository"

          chroot! build_path, "apt-get install mariadb-client libmariadb-dev -y", "Failed to install mariadb client"
        end
      end
    end
  end
end