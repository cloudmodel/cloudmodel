module CloudModel
  module Workers
    module Components
      class PhpComponentWorker < BaseComponentWorker
        def php_version
          CloudModel.config.php_version
        end

        def build build_path
          if @template.os_version =~ /ubuntu-/
            chroot! build_path, "add-apt-repository ppa:ondrej/php -y", "Failed to add php ppa"
            chroot! build_path, "apt-get update", "Failed to update apt"
          end

          packages = %w(php-fpm)
          packages += %w(php-curl php-mbstring php-zip php-gd php-dom)
          packages += %w(php-intl php-bcmath php-gmp php-apcu)

          packages.map! do |package|
            package.gsub(/^php-/, "php#{CloudModel.config.php_version}-")
          end

          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for deployment of php app"
        end
      end
    end
  end
end