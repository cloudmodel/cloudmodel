require 'spec_helper'

describe CloudModel::WebApps::WordpressWebApp do
  it { expect(subject).to be_a CloudModel::WebApp }

  it { expect(subject).to have_field(:mysql_host).of_type(String).with_default_value_of 'localhost' }
  it { expect(subject).to have_field(:mysql_port).of_type(Integer).with_default_value_of 3306 }
  it { expect(subject).to have_field(:mysql_user).of_type(String).with_default_value_of 'wordpress' }
  it { expect(subject).to have_field(:mysql_passwd).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:mysql_database).of_type(String).with_default_value_of 'wordpress' }

  it { expect(subject).to have_field(:wp_auth_key).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:wp_secure_auth_key).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:wp_logged_in_key).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:wp_nonce_key).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:wp_auth_salt).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:wp_secure_auth_salt).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:wp_logged_in_salt).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:wp_nonce_salt).of_type(String).with_default_value_of nil }

  it { expect(subject).to have_field(:wp_passwd).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:wp_allow_xmlrpc).of_type(Mongoid::Boolean).with_default_value_of false }

  describe 'set_mysql_passwd' do
    it 'should generate and assign 16 char random alphanumeric' do
      random = "01234567890abcdef".chars.shuffle.join
      expect(SecureRandom).to receive(:alphanumeric).with(16).and_return random
      subject.set_mysql_passwd
      expect(subject.mysql_passwd).to eq random
    end
  end

  describe 'set_salt_keys' do
    pending

    # self.wp_auth_key = generate_salt_key
    # self.wp_secure_auth_key = generate_salt_key
    # self.wp_logged_in_key = generate_salt_key
    # self.wp_nonce_key = generate_salt_key
    # self.wp_auth_salt = generate_salt_key
    # self.wp_secure_auth_salt = generate_salt_key
    # self.wp_logged_in_salt = generate_salt_key
    # self.wp_nonce_salt = generate_salt_key
  end

  describe 'needed_components' do
    it 'should require php, php_mysql, and php_imagemagick' do
      expect(subject.needed_components).to eq [:php, :php_mysql, :php_imagemagick]
    end
  end

  describe 'persistant_folders' do
    it 'should include "var/www/wp-content"' do
      expect(subject.persistant_folders).to include 'var/www/wp-content'
    end
  end

  describe 'generate_salt_key' do
    it 'should generate a 64 char alphanumeric' do
      random = "01234567890abcdef".chars.shuffle.join
      expect(SecureRandom).to receive(:alphanumeric).with(64).and_return random
      expect(subject.generate_salt_key).to eq random
    end
  end

  describe 'additional_allowed_params' do
    it 'should allow to config mysql' do
      expect(subject.additional_allowed_params).to include :mysql_host, :mysql_port, :mysql_user, :mysql_database
    end

    it 'should allow to set wordpress passwd for protecting admin and login' do
      expect(subject.additional_allowed_params).to include :wp_passwd
    end

    it 'should allow to allow wordpress xmlrpc' do
      expect(subject.additional_allowed_params).to include :wp_allow_xmlrpc
    end
  end

  describe '#fetch_app_command' do
    pending
    # # Cache files?
    # [
    #   'mkdir -p /opt/web-app',
    #   'cd /opt/web-app',
    #   'wget https://wordpress.org/latest.tar.gz',
    #   'tar xzf latest.tar.gz',
    #   'rm latest.tar.gz',
    #   'chown -R 100000:100000 /opt/web-app/wordpress'
    # ] * ' && '
  end

  describe 'config_files_to_render' do
    it 'should render wp-config template' do
      expect(subject.config_files_to_render['cloud_model/web_apps/wordpress_web_app/wp-config.php']).to eq ["/opt/web-app/wordpress/wp-config.php", 0644]
    end

    it 'should render passwd template' do
      expect(subject.config_files_to_render['cloud_model/web_apps/wordpress_web_app/htpasswd']).to eq ["/etc/nginx/.htpasswd-#{subject.id}-wordpress", 0600]
    end

    it 'should render init_mysql template' do
      expect(subject.config_files_to_render['cloud_model/web_apps/wordpress_web_app/init_mysql.sql']).to eq ["/root/init_wordpress_user.sql", 0600]
    end
  end
end