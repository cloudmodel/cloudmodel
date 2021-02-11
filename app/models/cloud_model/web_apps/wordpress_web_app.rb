module CloudModel
  module WebApps
    class WordpressWebApp < ::CloudModel::WebApp
      field :mysql_host, type: String, default: 'localhost'
      field :mysql_port, type: Integer, default: 3306
      field :mysql_user, type: String, default: 'wordpress'
      field :mysql_passwd, type: String, default: nil
      field :mysql_database, type: String, default: 'wordpress'

      field :wp_auth_key, type: String, default: nil
      field :wp_secure_auth_key, type: String, default: nil
      field :wp_logged_in_key, type: String, default: nil
      field :wp_nonce_key, type: String, default: nil
      field :wp_auth_salt, type: String, default: nil
      field :wp_secure_auth_salt, type: String, default: nil
      field :wp_logged_in_salt, type: String, default: nil
      field :wp_nonce_salt, type: String, default: nil

      before_create :set_mysql_passwd
      before_create :set_salt_keys

      def set_mysql_passwd
        self.mysql_passwd = SecureRandom.alphanumeric 16
      end

      def set_salt_keys
        self.wp_auth_key = generate_salt_key
        self.wp_secure_auth_key = generate_salt_key
        self.wp_logged_in_key = generate_salt_key
        self.wp_nonce_key = generate_salt_key
        self.wp_auth_salt = generate_salt_key
        self.wp_secure_auth_salt = generate_salt_key
        self.wp_logged_in_salt = generate_salt_key
        self.wp_nonce_salt = generate_salt_key
      end

      def needed_components
        [:php, :php_mysql, :php_imagemagick]
      end

      def persistant_folders
        [
          'var/www/wp-content'
        ]
      end

      def generate_salt_key
        SecureRandom.alphanumeric 64
      end

      def additional_allowed_params
        [:mysql_host, :mysql_port, :mysql_user, :mysql_database]
      end

      def self.fetch_app_command
        # Cache files?
        [
          'mkdir -p /opt/web-app',
          'cd /opt/web-app',
          'wget https://wordpress.org/latest.tar.gz',
          'tar xzf latest.tar.gz',
          'rm latest.tar.gz',
          'chown -R 100000:100000 /opt/web-app/wordpress'
        ] * ' && '
      end

      def self.config_files_to_render
        {
          'cloud_model/web_apps/wordpress_web_app/wp-config.php' => ["#{app_folder}/wp-config.php", 0644],
          'cloud_model/web_apps/wordpress_web_app/init_mysql.sql' => ["/root/init_wordpress_user.sql", 0600] # TODO: Find better way to init mysql
        }
      end
    end
  end
end
