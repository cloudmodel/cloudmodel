module CloudModel
  module WebApps
    # Roundcube webmail web application.
    #
    # Installs Roundcubemail, renders `config.inc.php` with IMAP/SMTP and
    # MariaDB settings, and generates a SQL initialisation script. The MySQL
    # password and DES session key are generated automatically on create.
    class RoundcubemailWebApp < ::CloudModel::WebApp
      # @!attribute [rw] mysql_host
      #   @return [String] MariaDB hostname (default: `"localhost"`)
      field :mysql_host, type: String, default: 'localhost'

      # @!attribute [rw] mysql_port
      #   @return [Integer] MariaDB port (default: 3306)
      field :mysql_port, type: Integer, default: 3306

      # @!attribute [rw] mysql_user
      #   @return [String] MariaDB user (default: `"roundcube"`)
      field :mysql_user, type: String, default: 'roundcube'

      # @!attribute [rw] mysql_passwd
      #   @return [String, nil] MariaDB password; auto-generated on create
      field :mysql_passwd, type: String, default: nil

      # @!attribute [rw] mysql_database
      #   @return [String] MariaDB database name (default: `"roundcubemail"`)
      field :mysql_database, type: String, default: 'roundcubemail'

      # @!attribute [rw] imap_host
      #   @return [String] IMAP server hostname (default: `"localhost"`)
      field :imap_host, type: String, default: 'localhost'

      # @!attribute [rw] imap_port
      #   @return [Integer] IMAP port (default: 993 — IMAPS)
      field :imap_port, type: Integer, default: 993

      # @!attribute [rw] smtp_host
      #   @return [String] SMTP server hostname (default: `"localhost"`)
      field :smtp_host, type: String, default:'localhost'

      # @!attribute [rw] smtp_port
      #   @return [Integer] SMTP submission port (default: 587)
      field :smtp_port, type: Integer, default: 587

      # @!attribute [rw] smtp_user
      #   @return [String] SMTP username; `"%u"` expands to the logged-in IMAP user
      field :smtp_user, type: String, default: '%u'

      # @!attribute [rw] smtp_passwd
      #   @return [String] SMTP password; `"%p"` expands to the logged-in IMAP password
      field :smtp_passwd, type: String, default: '%p'

      # @!attribute [rw] rcm_support_url
      #   @return [String] URL shown in the Roundcube support link
      field :rcm_support_url, type: String, default: ''

      # @!attribute [rw] rcm_product_name
      #   @return [String] product name shown in the UI (default: `"CloudModel Webmail"`)
      field :rcm_product_name, type: String, default: 'CloudModel Webmail'

      # @!attribute [rw] rcm_des_key
      #   @return [String, nil] 24-character DES key for session encryption; auto-generated on create
      field :rcm_des_key, type: String, default: nil

      # @!attribute [rw] rcm_plugins
      #   @return [Array<String>] list of Roundcube plugins to enable (default: `["archive", "zipdownload"]`)
      field :rcm_plugins, type: Array, default: ['archive', 'zipdownload']

      # @!attribute [rw] rcm_skin
      #   @return [String] Roundcube UI skin (default: `"elastic"`)
      field :rcm_skin, type: String, default: 'elastic'

      before_create :set_rcm_des_key
      before_create :set_mysql_passwd

      def set_rcm_des_key
        self.rcm_des_key = "rcmail-#{SecureRandom.alphanumeric 16}"
      end

      def set_mysql_passwd
        self.mysql_passwd = SecureRandom.alphanumeric 16
      end

      # mysql roundcubemail < SQL/mysql.initial.sql
      def needed_components
        [:php, :php_mysql, :php_imap]
      end

      # @return [Array<String>] plugin names available for selection
      def self.available_rcm_plugins
        ['archive', 'zipdownload']
      end

      # @return [Array<String>] skin names available for selection
      def self.available_rcm_skins
        ['elastic', 'classic', 'larry']
      end

      def additional_allowed_params
        [:rcm_product_name, :rcm_support_url, :rcm_skin, :mysql_host, :mysql_port, :mysql_user, :mysql_database, :imap_host, :imap_port, :smtp_host, :smtp_port, :smtp_user, :smtp_passwd, rcm_plugins: []]
      end

      def self.fetch_app_command
        rcm_version = '1.4.11' # TODO: Get latest RCM version from internet
        # Cache files?
        [
          'mkdir -p /opt/web-app',
          'cd /opt/web-app',
          "wget https://github.com/roundcube/roundcubemail/releases/download/#{rcm_version}/roundcubemail-#{rcm_version}-complete.tar.gz",
          "tar xzf roundcubemail-#{rcm_version}-complete.tar.gz",
          "rm roundcubemail-#{rcm_version}-complete.tar.gz",
          "mv roundcubemail-#{rcm_version} roundcubemail",
          'chown -R 100000:100000 /opt/web-app/roundcubemail'
        ] * ' && '
      end

      def config_files_to_render
        {
          'cloud_model/web_apps/roundcubemail_web_app/config.inc.php' => ["#{self.class.app_folder}/config/config.inc.php", 0644],
          'cloud_model/web_apps/roundcubemail_web_app/init_mysql.sql' => ["/root/init_roundcube_user.sql", 0600] # TODO: call init_db
        }
      end

      def init_db
        [
          "mysql </root/init_roundcube_user.sq",
          "mysql #{mysql_database} <#{app_folder}/SQL/mysql.initial.sql"
        ]
      end
    end
  end
end