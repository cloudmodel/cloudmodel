module CloudModel
  module Workers
    module Components
      class PhpMysqlComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install php#{CloudModel.config.php_version}-mysql -y", "Failed to install php mysql module"
        end
      end
    end
  end
end