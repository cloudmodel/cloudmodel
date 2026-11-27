module CloudModel
  module Workers
    module Components
      # Component worker that installs MySQL Community Server into a guest
      # template chroot, from MySQL's own apt repository of the release series
      # (`mysql-8.4-lts`, `mysql-8.0`).
      #
      # The repository is signed with the MySQL release engineering key; it is
      # fetched by fingerprint from the Ubuntu keyserver and the build fails
      # unless the keyring holds exactly that primary key. MySQL publishes its
      # Debian and Ubuntu packages for amd64 only.
      class MysqlComponentWorker < BaseComponentWorker
        # Release series installed when the component carries no version.
        MYSQL_SERIES = "8.4".freeze

        # Fingerprint of the MySQL release engineering key.
        MYSQL_REPO_KEY = "BCA43417C3B485DD128EC6D4B7B3B788A8D3785C".freeze

        KEYRING = "/usr/share/keyrings/mysql-keyring.gpg".freeze

        ARCHES = %w[amd64].freeze

        def series
          @options[:component].try(:version).presence || MYSQL_SERIES
        end

        # Repository component of the series: LTS series are `mysql-<x.y>-lts`,
        # 8.0 is `mysql-8.0`.
        def repository
          self.class.repository_for series
        end

        # @param series [String] e.g. `"8.4"`
        # @return [String] repository component of the series
        def self.repository_for series
          series == '8.0' ? "mysql-#{series}" : "mysql-#{series}-lts"
        end

        def build build_path
          unless ARCHES.include? @template.arch
            raise "MySQL publishes its apt packages for #{ARCHES.join(', ')} only, not for #{@template.arch}"
          end

          chroot! build_path, "apt-get install curl ca-certificates gnupg -y", "Failed to install key management"
          chroot! build_path, "curl -fsSL #{"#{PerconaRepository::KEYSERVER}#{MYSQL_REPO_KEY}".shellescape} | gpg --batch --no-tty --dearmor > #{KEYRING}", "Failed to fetch MySQL repository key"
          chroot! build_path, "test \"$(gpg --batch --no-tty --show-keys --with-colons #{KEYRING} | awk -F: '$1 == \"pub\" { getline; print $10 }')\" = #{MYSQL_REPO_KEY}", "MySQL repository keyring does not hold exactly the key #{MYSQL_REPO_KEY}"
          chroot build_path, "gpgconf --kill all"

          os = @template.os_version =~ /ubuntu-/ ? 'ubuntu' : 'debian'
          codename = CloudModel.debian_short_name(@template.os_version)
          chroot! build_path, "echo #{"deb [signed-by=#{KEYRING}] http://repo.mysql.com/apt/#{os} #{codename} #{repository}".shellescape} > /etc/apt/sources.list.d/#{repository}.list", "Failed to add MySQL #{repository} repository"

          chroot! build_path, "apt-get update", "Failed to update packages"
          chroot! build_path, "DEBIAN_FRONTEND=noninteractive apt-get install mysql-community-server -y", "Failed to install MySQL #{series}"
        end
      end
    end
  end
end
