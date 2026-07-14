require "cloud_model/config_modules/api"

module CloudModel
  # Central configuration, set from the host app's initializer via a
  # `configure` block. Every option has a default (see the getters below).
  #
  # A full, categorised reference of all options — defaults, allowed values and
  # purpose — lives in `doc/configuration.md`.
  class Config
    attr_writer :data_directory, :backup_directory, :bundle_command
    # Max number of backups (replica sets / guests) to run concurrently in
    # backup_all. Backups mostly shell out (mongodump / zfs send), so threads
    # overlap their wait. Default 4. Note: each concurrent backup uses a Mongoid
    # connection, so keep this <= the Mongoid pool size.
    attr_writer :backup_concurrency
    attr_writer :skip_sync_images
    # ZFS dataset guest template builds are created under (on the build host)
    attr_writer :build_dataset
    # ZFS compression for build volumes (guest/core templates AND web-image
    # artifacts). One of "lz4" (default, universal, near-free CPU), "zstd"
    # (better ratio but needs OpenZFS >= 2.0 on every host that receives it) or
    # "off". See {#zfs_compression}.
    attr_writer :zfs_compression
    # SSH private key used to reach hosts from the controller machine
    attr_writer :ssh_key_file
    # SSH private key that can read the private git repos referenced as
    # git-source gems in a WebImage's Gemfile. Copied into the throwaway build
    # system chroot for `bundle install`, then destroyed with it.
    attr_writer :git_ssh_key_file
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
    attr_writer :monitoring_sample_retention
    attr_accessor :issue_url

    attr_accessor :build_host_name

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

    def backup_concurrency
      @backup_concurrency || 4
    end

    def bundle_command
      @bundle_command || '/usr/local/rvm/bin/rvm default do bundle'
    end

    # If true do not sync images on deploy
    def skip_sync_images
      @skip_sync_images || false
    end

    # ZFS dataset guest template builds are created under; lives in the same
    # pool as the LXD container datasets, so deploys can `zfs clone`.
    def build_dataset
      @build_dataset || 'guests/build'
    end

    # SSH private key used to reach hosts from the controller machine
    def ssh_key_file
      @ssh_key_file || "#{data_directory}/keys/id_rsa"
    end

    def git_ssh_key_file
      @git_ssh_key_file || File.expand_path('~/.ssh/id_rsa')
    end

    # ZFS compression for build volumes (templates + web-image artifacts).
    # "lz4" is available in every OpenZFS and near-free on CPU, so builds,
    # deploy clones and cross-host `zfs send`/receive work everywhere. "zstd"
    # compresses better (~3.2x vs ~2.35x) but needs OpenZFS >= 2.0 on every
    # host it is sent to; set it only when the whole cloud supports it. "off"
    # disables compression.
    def zfs_compression
      @zfs_compression || 'lz4'
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
      @ruby_version || "3.4"
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

    # Round-robin retention window per monitoring sample resolution. Samples
    # older than the window for their resolution are expired automatically by
    # MongoDB (TTL index on CloudModel::MonitoringSample#expires_at).
    #
    # Defaults keep high-resolution data briefly and downsampled data for long
    # time graphs. Override (whole hash) via the configure block.
    # @return [Hash{Symbol=>ActiveSupport::Duration}]
    def monitoring_sample_retention
      @monitoring_sample_retention || {
        raw: 2.days,
        hour: 90.days,
        day: 3.years
      }
    end
  end
end