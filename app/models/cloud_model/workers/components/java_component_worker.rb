module CloudModel
  module Workers
    module Components
      class JavaComponentWorker < BaseComponentWorker
        def build build_path
          # Java needs man directory
          mkdir_p "#{build_path}/usr/share/man/man1/"

          chroot! build_path, "apt-get install default-jre-headless -y", "Failed to install Java"
        end
      end
    end
  end
end