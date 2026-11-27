module CloudModel
  module Services
    # MySQL 8 database service embedded in a {Guest}, next to {Mariadb} as
    # the choice for applications that need MySQL itself (MariaDB has
    # diverged from it). The server packages come from the distribution in
    # {#mysql_distribution}, like the {Mongodb} service: MySQL Community from
    # MySQL's repository or Percona Server for MySQL (GPL) from Percona's.
    # Both are the same server down to the data files, unit and paths, so a
    # guest switches by a redeploy.
    #
    # Listens on localhost only: the applications using it run in the same
    # guest and log in over TCP to `127.0.0.1` with their own user, root logs
    # in over the socket (`auth_socket`) only. The data directory is
    # `/var/lib/mysql`, meant to be the guest's data volume; an empty one is
    # initialised on the first start.
    #
    # Usage telemetry to the vendor is a switch of this service, off by
    # default; only Percona's packages send any (the server's telemetry
    # component and the telemetry agent, a hard dependency of the server
    # package).
    #
    # Backups: the data volume is snapshotted by the volume backup; in
    # addition the service backup takes a consistent `mysqldump` of all
    # databases.
    class Mysql < Base
      include CloudModel::Mixins::ServerPlatform
      include CloudModel::Mixins::BackupTools

      DATA_DIR = '/var/lib/mysql'.freeze

      # @!attribute [rw] port
      #   @return [Integer] client port on localhost (default: 3306)
      field :port, type: Integer, default: 3306

      # @!attribute [rw] mysql_distribution
      #   @return [String] where the server packages come from: `"percona"`
      #     (Percona Server for MySQL from Percona's repository, the default)
      #     or `"mysql"` (MySQL Community from MySQL's repository, amd64 only)
      field :mysql_distribution, type: String, default: 'percona'

      # @!attribute [rw] mysql_version
      #   @return [String, nil] release series (e.g. `"8.4"`); blank uses
      #     {CloudModel::Workers::Components::MysqlComponentWorker::MYSQL_SERIES}
      field :mysql_version, type: String, default: nil

      # @!attribute [rw] telemetry
      #   @return [Boolean] send usage telemetry to the vendor (off by default)
      field :telemetry, type: Mongoid::Boolean, default: false

      DISTRIBUTIONS = %w(mysql percona).freeze

      validates :mysql_distribution, inclusion: {in: DISTRIBUTIONS}
      validate :guest_must_not_have_mariadb

      # @return [Boolean] whether the server comes from Percona
      def percona?
        mysql_distribution == 'percona'
      end

      def self.server_distribution_field
        :mysql_distribution
      end

      def self.server_version_field
        :mysql_version
      end

      # Lines offered where the platform table knows nothing.
      def self.default_lines _distribution
        %w(8.0 8.4)
      end

      # @return [Symbol] component name of the distribution (without line)
      def component_for distribution
        distribution == 'percona' ? :percona_server : :mysql
      end

      # The blank version means the default series.
      def server_line
        effective_mysql_version
      end

      def kind
        :mysql
      end

      # @return [String] the release series this service runs on
      def effective_mysql_version
        mysql_version.presence || CloudModel::Workers::Components::MysqlComponentWorker::MYSQL_SERIES
      end

      def components_needed
        server = percona? ? :"percona_server@#{effective_mysql_version}" : :"mysql@#{effective_mysql_version}"
        ([server] + super).uniq
      end

      def used_ports
        [[port, :tcp]]
      end

      def stop_timeout
        60
      end

      # Alive check over the root socket inside the guest.
      def service_status
        success, output = guest.exec "mysqladmin ping --silent"
        if success
          { alive: true }
        else
          { key: :not_reachable, error: "mysqladmin ping failed: #{output.to_s.strip[0, 200]}", severity: :critical }
        end
      rescue Exception => e
        { key: :not_reachable, error: "#{e.class}\n\n#{e}", severity: :critical }
      end

      def backupable?
        true
      end

      def backup_data_mount_point
        DATA_DIR.delete_prefix('/')
      end

      # Service-level backup: a consistent `mysqldump` of all databases,
      # taken inside the guest, pulled to the host and fetched into the
      # backup directory.
      # @return [Boolean]
      def backup
        return false unless has_backups

        timestamp = Time.now.strftime "%Y%m%d%H%M%S"
        target = "#{backup_directory}/#{timestamp}"
        guest_file = "/var/tmp/mysql-dump-#{timestamp}.sql.gz"
        host_file = "/tmp/#{guest.name}-mysql-dump-#{timestamp}.sql.gz"

        FileUtils.mkdir_p target

        # lxc exec runs no shell in the guest: the pipeline gets its own.
        dump = "set -o pipefail; mysqldump --single-transaction --routines --triggers --events --all-databases | gzip > #{guest_file.shellescape}"
        success, output = guest.exec "bash -c #{dump.shellescape}"
        unless success
          CloudModel.backup_log "mysqldump failed: #{output.to_s.strip.lines.last.to_s.strip}"
          FileUtils.rm_rf target
          return false
        end

        guest.host.exec! "lxc file pull #{guest.current_lxd_container.name.shellescape}#{guest_file} #{host_file.shellescape}", "Failed to pull mysql dump from guest"
        guest.host.sftp.download! host_file, "#{target}/all-databases.sql.gz"

        FileUtils.rm_f "#{backup_directory}/latest"
        # Relative link: survives Capistrano release pruning.
        FileUtils.ln_s timestamp, "#{backup_directory}/latest"
        record_successful_backup
        cleanup_backups

        true
      rescue Exception => e
        CloudModel.backup_log "mysqldump failed: #{e.message}"
        FileUtils.rm_rf target
        false
      ensure
        guest.exec "rm -f #{guest_file.shellescape}" rescue nil
        guest.host.exec "rm -f #{host_file.shellescape}" rescue nil
      end

      # Restoring is a manual procedure: stop the applications, then feed
      # the dump to `mysql` inside the guest.
      def restore timestamp='latest'
        raise CloudModel::BackupError, "MySQL dumps are restored by hand: zcat #{backup_directory}/#{timestamp}/all-databases.sql.gz | mysql inside the guest"
      end

      private

      # Both install the `mysql` unit, /etc/mysql and /var/lib/mysql.
      def guest_must_not_have_mariadb
        return unless guest
        return unless guest.services.any? { |s| s.is_a?(CloudModel::Services::Mariadb) }

        errors.add :base, :mysql_beside_mariadb
      end
    end
  end
end
