module CloudModel
  module WebApps
    class NextcloudWebApp < ::CloudModel::WebApp
      field :mysql_host, type: String, default: 'localhost'
      field :mysql_port, type: Integer, default: 3306
      field :mysql_user, type: String, default: 'nextcloud'
      field :mysql_passwd, type: String, default: nil
      field :mysql_database, type: String, default: 'nextcloud'

      field :nextcloud_instanceid, type: String, default: nil
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
        nextcloud_version = '20.0.7' # TODO: Get latest RCM version from internet
        # Cache files?
        [
          'mkdir -p /opt/web-app',
          'cd /opt/web-app',
          "wget https://download.nextcloud.com/server/releases/nextcloud-#{nextcloud_version}.tar.bz2",
          "tar xjf nextcloud-#{nextcloud_version}.tar.bz2",
          "rm nextcloud-#{nextcloud_version}.tar.bz2",
          'chown -R 100000:100000 /opt/web-app/nextcloud'
        ] * ' && '
      end

      def self.config_files_to_render
        {
          'cloud_model/web_apps/nextcloud_web_app/config.php' => ["#{app_folder}/config/config.php", 0644],
          'cloud_model/web_apps/nextcloud_web_app/init_mysql.sql' => ["/root/init_nextcloud_user.sql", 0600] # TODO: Find better way to init mysql
        }
      end
    end
  end
end
