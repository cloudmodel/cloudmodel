module CloudModel
  module Workers
    module Components
      class MariadbComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install mariadb-server galera -y", "Failed to install mariadb"
        end
      end
    end
  end
end