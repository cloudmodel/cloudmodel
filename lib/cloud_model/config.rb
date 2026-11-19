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
    # Backup retention (dumps and ZFS volume snapshots), see
    # Mixins::BackupTools.disposable_timestamps.
    attr_writer :backup_retention
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
    # Key pair hosts use among themselves to stream build volumes directly
    # (zfs send | zfs receive) instead of through the controller. Generated on
    # first use; distributed with `rake cloudmodel:host:deploy_zfs_sync_key`.
    attr_writer :zfs_sync_key_file
    # SSH private key that can read the private git repos referenced as
    # git-source gems in a WebImage's Gemfile. Copied into the throwaway build
    # system chroot for `bundle install`, then destroyed with it.
    attr_writer :git_ssh_key_file
    # Use external IP, useful for testing without setting up a VPN for your development box or if you have troubles with tinc
    attr_writer :use_external_ip
    attr_writer :dns_servers, :job_queue, :additional_hosts

    attr_writer :ubuntu_mirror, :ubuntu_deb_src, :ubuntu_version
    # Unattended installation of the distribution's security updates on
    # hosts and guests (templates + live push). true by default.
    attr_writer :unattended_upgrades
    attr_writer :debian_version
    attr_writer :php_version, :ruby_version

    attr_accessor :admin_email, :email_domain
    attr_writer :dns_domains

    attr_writer :host_mac_address_prefix_init
    attr_writer :tinc_network, :tinc_client_name, :tinc_mtu, :tinc_cipher, :tinc_digest, :tinc_udp_buffer, :tinc_txqueuelen
    attr_writer :check_mk_agent_version
    attr_writer :monitoring_guest_concurrency
    attr_writer :monitoring_restart_pause

    attr_writer :backup_hosts, :monitoring_notifiers
    attr_writer :monitoring_sample_retention
    # Prefix for the ZFS backup snapshots (`<dataset>@<prefix><timestamp>`).
    # The pruner and incremental-base lookup key on it, so an app that already
    # has snapshots under a different prefix must set it to that value.
    attr_writer :backup_snapshot_prefix
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

    # @return [Hash] {recent:, days:, weeks:, months:} — the newest `recent`
    #   backups plus the newest backup of each of the last `days` calendar
    #   days, `weeks` calendar weeks and `months` calendar months
    def backup_retention
      {recent: 3, days: 6, weeks: 6, months: 6}.merge(@backup_retention || {})
    end

    # Prefix for ZFS backup snapshots (see the writer above). Generic default;
    # override to match pre-existing snapshots created under another prefix.
    def backup_snapshot_prefix
      @backup_snapshot_prefix || 'cm-bkp-'
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

    # Private key of the host-to-host ZFS sync pair (public key beside it as
    # `.pub`). See {CloudModel::ZfsSyncKey}.
    def zfs_sync_key_file
      @zfs_sync_key_file || "#{data_directory}/keys/zfs_sync"
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

    def unattended_upgrades
      @unattended_upgrades.nil? ? true : @unattended_upgrades
    end

    def debian_version
      @debian_version || "12"
    end

    def ubuntu_major_version
      ubuntu_version.split('.')[0..1] * '.'
    end

    def php_version
      @php_version || "8.4"
    end

    def ruby_version
      @ruby_version || "3.4"
    end

    def dns_domains
      @dns_domains ||= []
    end

    # Static name → address mappings rendered into every guest's `/etc/hosts`
    # on deploy. Useful to override public names with in-cluster addresses
    # (split-horizon), e.g. on development clusters that mirror production
    # hostnames: `{'app.example.com' => '10.0.0.5'}`.
    # @return [Hash{String=>String}]
    def additional_hosts
      @additional_hosts ||= {}
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

    # MTU of the tinc interface between hosts, fixed instead of discovered:
    # while tinc 1.0 re-measures a path it answers with provisional MTUs (down
    # to 68), and established TCP connections never grow their segments back.
    # Has to leave room below the uplink MTU for UDP and tinc's own headers
    # (a 1500 uplink carries about 1445 with blowfish/SHA1).
    def tinc_mtu
      @tinc_mtu || 1400
    end

    # Transmit queue length of the VPN interface. The kernel default of 500
    # packets drops the tail of a burst (a dump streaming to another host)
    # while the daemon is still encrypting the head.
    def tinc_txqueuelen
      @tinc_txqueuelen || 2000
    end

    # Cipher and digest a tinc node announces for the packets sent to it
    # (tinc 1.0 reads them from the node's own host file, so nodes can switch
    # one by one). AES needs no OpenSSL legacy provider, unlike tinc's old
    # Blowfish default.
    def tinc_cipher
      @tinc_cipher || 'aes-256-cbc'
    end

    def tinc_digest
      @tinc_digest || 'sha256'
    end

    # Send and receive buffer of tinc's UDP socket, in bytes. A TCP burst
    # from one peer (a database result batch is ~1 MB in ~850 packets)
    # lands on this socket faster than tincd drains it; with the kernel
    # default of ~200 KB much of such a burst is dropped and the sender's
    # TCP window collapses — measured 2× slower cursor walks over a 25 ms
    # path. The host's net.core.rmem_max/wmem_max are raised to twice this.
    def tinc_udp_buffer
      @tinc_udp_buffer || 8 * 1024 * 1024
    end

    # Checkmk release branch the plain agent script is taken from (the
    # agent is a single bash script, installed from the project's GitHub
    # into /usr/bin/check_mk_agent on image build and every plugin push).
    def check_mk_agent_version
      @check_mk_agent_version || '2.2.0'
    end

    # Guests checked at the same time per host during a monitoring cycle
    # (hosts already run in parallel). Each worker opens its own SSH session
    # to the host, on top of the host check's one — keep the sum below any
    # rate limit the hosts put on new SSH connections.
    def monitoring_guest_concurrency
      @monitoring_guest_concurrency || 3
    end

    # Seconds the monitoring service unit pauses between two cycles
    # (RestartSec). The cycle stagger between admin hosts counts with it.
    def monitoring_restart_pause
      @monitoring_restart_pause || 180
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