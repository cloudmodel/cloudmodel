module CloudModel
  module WebApps
    # Nextcloud file-sharing and collaboration web application.
    #
    # Installs the latest Nextcloud release into `/opt/web-app/nextcloud`,
    # renders the `config.php` configuration file, initialises the MariaDB
    # user/database via a SQL template, and wires up a systemd cron timer for
    # background jobs. The MySQL password is generated automatically on create.
    class NextcloudWebApp < ::CloudModel::WebApp
      # @!attribute [rw] mysql_host
      #   @return [String] MariaDB hostname (default: `"localhost"`)
      field :mysql_host, type: String, default: 'localhost'

      # @!attribute [rw] mysql_port
      #   @return [Integer] MariaDB port (default: 3306)
      field :mysql_port, type: Integer, default: 3306

      # @!attribute [rw] mysql_user
      #   @return [String] MariaDB user (default: `"nextcloud"`)
      field :mysql_user, type: String, default: 'nextcloud'

      # @!attribute [rw] mysql_passwd
      #   @return [String, nil] MariaDB password; auto-generated on create
      field :mysql_passwd, type: String, default: nil

      # @!attribute [rw] mysql_database
      #   @return [String] MariaDB database name (default: `"nextcloud"`)
      field :mysql_database, type: String, default: 'nextcloud'

      # @!attribute [rw] nextcloud_instanceid
      #   @return [String, nil] Nextcloud instance ID stored in `config.php`
      field :nextcloud_instanceid, type: String, default: nil

      # @!attribute [rw] nextcloud_passwordsalt
      #   @return [String, nil] Nextcloud password salt stored in `config.php`
      field :nextcloud_passwordsalt, type: String, default: nil

      before_create :set_mysql_passwd

      def set_mysql_passwd
        self.mysql_passwd = SecureRandom.alphanumeric 16
      end

      # occ db:add-missing-indices
      def needed_components
        [:php, :php_mysql, :php_imagemagick]
      end

      def additional_allowed_params
        [:mysql_host, :mysql_port, :mysql_user, :mysql_database, :nextcloud_instanceid]
      end

      def self.fetch_app_command
        #nextcloud_version = 'nextcloud-28.0.1' # TODO: Get latest RCM version from internet
        nextcloud_version = 'latest'
        # Cache files?
        [
          'mkdir -p /opt/web-app',
          'cd /opt/web-app',
          "wget https://download.nextcloud.com/server/releases/#{nextcloud_version}.tar.bz2",
          "tar xjf #{nextcloud_version}.tar.bz2",
          "rm #{nextcloud_version}.tar.bz2",
          'chown -R 100000:100000 /opt/web-app/nextcloud'
        ] * ' && '
      end

      def config_files_to_render
        {
          'cloud_model/web_apps/nextcloud_web_app/config.php' => ["#{self.class.app_folder}/config/config.php", 0644],
          'cloud_model/web_apps/nextcloud_web_app/init_mysql.sql' => ["/root/init_nextcloud_user.sql", 0600], # TODO: Find better way to init mysql
          'cloud_model/web_apps/nextcloud_web_app/nextcloudcron.service' => ["/etc/systemd/system/nextcloudcron.service", 0755],
          'cloud_model/web_apps/nextcloud_web_app/nextcloudcron.timer' => ["/etc/systemd/system/nextcloudcron.timer", 0755],
        }
      end

      def configure
        [
          ["ln -s /etc/systemd/system/nextcloudcron.timer /etc/systemd/system/timers.target.wants/nextcloudcron.timer", "enable nextcloudcron timer"]
        ]
      end
    end
  end
end
