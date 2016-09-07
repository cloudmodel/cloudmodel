module CloudModel
  module Components
    class JavaWorker < BaseWorker
      def build build_path
        puts "        Install Java"
        # Java needs man directory
        mkdir_p "#{build_path}/usr/share/man/man1/"
        
        chroot! build_path, "apt-get install openjdk-8-jre-headless -y", "Failed to install java"
      end
    end
  end
end