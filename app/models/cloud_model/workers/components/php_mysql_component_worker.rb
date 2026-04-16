module CloudModel
  module Workers
    module Components
      # Component worker that installs the PHP MySQL/MariaDB extension into a guest template chroot.
      #
      # Installs `phpN-mysql` where N is the configured PHP version.
      class PhpMysqlComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install php#{CloudModel.config.php_version}-mysql -y", "Failed to install php mysql module"
        end
      end
    end
  end
end