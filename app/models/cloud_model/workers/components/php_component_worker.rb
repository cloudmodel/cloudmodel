module CloudModel
  module Workers
    module Components
      # Component worker that installs PHP-FPM and common PHP extensions into
      # a guest template chroot.
      #
      # The PHP major comes from `CloudModel.config.php_version` and is
      # installed from the PHP maintainers' repositories rather than the
      # distribution's single packaged version: the `ondrej/php` PPA on
      # Ubuntu, `packages.sury.org` on Debian (the same packages, built for
      # Debian). Both carry every supported major, so the version is a
      # configuration choice and security releases arrive within hours.
      # Installs `php-fpm`, `php-curl`, `php-mbstring`, `php-zip`, `php-gd`,
      # `php-dom`, `php-intl`, `php-bcmath`, `php-gmp`, and `php-apcu`.
      class PhpComponentWorker < BaseComponentWorker
        SURY_KEYRING_URL = 'https://packages.sury.org/debsuryorg-archive-keyring.deb'.freeze
        SURY_KEYRING = '/usr/share/keyrings/debsuryorg-archive-keyring.gpg'.freeze
        SURY_REPOSITORY = 'https://packages.sury.org/php/'.freeze
        SURY_LIST = '/etc/apt/sources.list.d/php.list'.freeze

        def php_version
          CloudModel.config.php_version
        end

        def build build_path
          if @template.os_version =~ /ubuntu-/
            chroot! build_path, "add-apt-repository ppa:ondrej/php -y", "Failed to add php ppa"
          else
            add_sury_repository build_path
          end
          chroot! build_path, "apt-get update", "Failed to update apt"

          packages = %w(php-fpm)
          packages += %w(php-curl php-mbstring php-zip php-gd php-dom)
          packages += %w(php-intl php-bcmath php-gmp php-apcu)

          packages.map! do |package|
            package.gsub(/^php-/, "php#{CloudModel.config.php_version}-")
          end

          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for deployment of php app"
        end

        # The sury.org repository the way its README sets it up: the signing
        # key as the keyring package (so key rotations arrive as updates),
        # the source pinned to that keyring and the template's Debian release.
        def add_sury_repository build_path
          codename = CloudModel.debian_short_name @template.os_version
          chroot! build_path, "curl -fsSLo /tmp/debsuryorg-archive-keyring.deb #{SURY_KEYRING_URL} && dpkg -i /tmp/debsuryorg-archive-keyring.deb && rm -f /tmp/debsuryorg-archive-keyring.deb", "Failed to install the sury.org keyring"
          chroot! build_path, "echo 'deb [signed-by=#{SURY_KEYRING}] #{SURY_REPOSITORY} #{codename} main' > #{SURY_LIST}", "Failed to add the sury.org php repository"
        end
      end
    end
  end
end
