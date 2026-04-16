module CloudModel
  module Workers
    module Components
      # Component worker that installs MariaDB server and Galera arbitrator
      # into a guest template chroot.
      class MariadbComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install mariadb-server galera-arbitrator-4 -y", "Failed to install mariadb"
        end
      end
    end
  end
end