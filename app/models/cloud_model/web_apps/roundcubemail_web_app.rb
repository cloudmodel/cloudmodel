module CloudModel
  module WebApps
    class RoundcubemailWebApp < ::CloudModel::WebApp
      field :mysql_host, type: String, default: 'localhost'
      field :mysql_port, type: Integer, default: 3306
      field :mysql_user, type: String, default: 'roundcube'
      field :mysql_passwd, type: String, default: nil
      field :mysql_database, type: String, default: 'roundcubemail'

      field :imap_host, type: String, default: 'localhost'
      field :imap_port, type: Integer, default: 993
      field :smtp_host, type: String, default:'localhost'
      field :smtp_port, type: Integer, default: 587
      field :smtp_user, type: String, default: '%u'
      field :smtp_passwd, type: String, default: '%p'

      field :rcm_support_url, type: String, default: ''
      field :rcm_product_name, type: String, default: 'CloudModel Webmail'
      field :rcm_des_key, type: String, default: nil

      field :rcm_plugins, type: Array, default: ['archive', 'zipdownload']
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

      def self.available_rcm_plugins
        ['archive', 'zipdownload']
      end

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

      def self.config_files_to_render
        {
          'cloud_model/web_apps/roundcubemail_web_app/config.inc.php' => ["#{app_folder}/config/config.inc.php", 0644],
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