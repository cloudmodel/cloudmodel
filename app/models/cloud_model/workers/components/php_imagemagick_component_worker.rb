module CloudModel
  module Workers
    module Components
      class PhpImagemagickComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install php#{CloudModel.config.php_version}-imagick -y", "Failed to install php imagemagick module"
        end
      end
    end
  end
end