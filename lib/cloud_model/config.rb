require "cloud_model/config_modules/api"

module CloudModel
  class Config
    attr_writer :data_directory, :backup_directory, :bundle_command
    attr_writer :skip_sync_images
    # Use external IP, useful for testing without setting up a VPN for your development box or if you have troubles with tinc
    attr_writer :use_external_ip
    attr_writer :dns_servers, :job_queue

    attr_writer :ubuntu_mirror, :ubuntu_deb_src, :ubuntu_version
    attr_writer :debian_version
    attr_writer :php_version, :ruby_version

    attr_accessor :admin_email, :email_domain
    attr_writer :dns_domains

    attr_writer :host_mac_address_prefix_init
    attr_writer :tinc_network, :tinc_client_name

    attr_writer :backup_hosts, :monitoring_notifiers
    attr_accessor :issue_url

    def initialize(&block)
      configure(&block) if block_given?
    end

    # Configure your CloudModel Rails Application with the given parameters in
    # the block. For possible options see above.
    def configure(&block)
      yield(self)
    end

    def api
      @api_module ||= CloudModel::ConfigModules::Api.new
    end

    def data_directory
      @data_directory || "#{Rails.root}/data"
    end

    def backup_directory
      @backup_directory || "#{data_directory}/backups"
    end

    def bundle_command
      @bundle_command || '/usr/local/rvm/bin/rvm default do bundle'
    end

    # If true do not sync images on deploy
    def skip_sync_images
      @skip_sync_images || false
    end

    def use_external_ip
      @use_external_ip || false
    end

    def dns_servers
      @dns_servers || %w(1.1.1.1 8.8.8.8 9.9.9.10)
    end

    def job_queue
      @job_queue || :default
    end

    def ubuntu_mirror
      @ubuntu_mirror || 'http://archive.ubuntu.com/ubuntu/'
    end

    def ubuntu_deb_src
      if @ubuntu_deb_src.nil?
        true
      else
        @ubuntu_deb_src
      end
    end

    def ubuntu_version
      @ubuntu_version || "22.04.4"
    end

    def debian_version
      @debian_version || "12"
    end

    def ubuntu_major_version
      ubuntu_version.split('.')[0..1] * '.'
    end

    def php_version
      @php_version || "8.2"
    end

    def ruby_version
      @ruby_version || "3.2"
    end

    def dns_domains
      @dns_domains ||= []
    end

    def host_mac_address_prefix_init
      @host_mac_address_prefix_init || '00:00'
    end

    def tinc_network
      @tinc_network || '10.42.0.0/16'
    end

    def tinc_client_name
      @tinc_client_name || 'cloudmodel'
    end

    def backup_hosts
      @backup_hosts ||= []
    end

    def monitoring_notifiers
      @monitoring_notifiers || []
    end
  end
end