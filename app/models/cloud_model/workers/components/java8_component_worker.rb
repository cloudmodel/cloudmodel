module CloudModel
  module Workers
    module Components
      class Java8ComponentWorker < BaseComponentWorker
        def build build_path
          # Java needs man directory
          mkdir_p "#{build_path}/usr/share/man/man1/"

          chroot! build_path, "apt-get install openjdk-8-jre-headless -y", "Failed to install Java 8"
        end
      end
    end
  end
end