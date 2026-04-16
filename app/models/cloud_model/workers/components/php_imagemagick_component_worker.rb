module CloudModel
  module Workers
    module Components
      # Component worker that installs the PHP Imagick extension into a guest template chroot.
      #
      # Installs `phpN-imagick` where N is the configured PHP version.
      class PhpImagemagickComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install php#{CloudModel.config.php_version}-imagick -y", "Failed to install php imagemagick module"
        end
      end
    end
  end
end