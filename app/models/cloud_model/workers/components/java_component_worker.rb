module CloudModel
  module Workers
    module Components
      class JavaComponentWorker < BaseComponentWorker
        def javaversion
          @options[:component].try(:version)
        end

        def build build_path
          # Java needs man directory
          mkdir_p "#{build_path}/usr/share/man/man1/"

          if javaversion
            chroot! build_path, "apt-get install openjdk-#{javaversion}-jre-headless -y", "Failed to install Java #{javaversion}"
          else
            chroot! build_path, "apt-get install default-jre-headless -y", "Failed to install Java"
          end
        end
      end
    end
  end
end