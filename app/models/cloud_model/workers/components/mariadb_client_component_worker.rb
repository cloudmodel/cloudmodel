module CloudModel
  module Workers
    module Components
      class MariadbClientComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install mariadb-client -y", "Failed to install mariadb client"
        end
      end
    end
  end
end