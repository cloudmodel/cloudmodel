require 'mysql2'

module CloudModel
  module Services
    # MariaDB/MySQL database service embedded in a {Guest}.
    #
    # Supports standalone and Galera multi-master replication. When assigned to
    # a {MariadbGaleraCluster}, `mariadb_galera_port` is used for the Galera
    # replication traffic. Backups use `mysqldump --all-databases`.
    class Mariadb < Base
      # @!attribute [rw] port
      #   @return [Integer] MariaDB client port (default: 3306)
      field :port, type: Integer, default: 3306

      # @!attribute [rw] mariadb_galera_port
      #   @return [Integer] Galera replication port (default: 4567)
      field :mariadb_galera_port, type: Integer, default: 4567

      # @!attribute [rw] mariadb_galera_cluster
      #   @return [CloudModel::MariadbGaleraCluster, nil] the Galera cluster this node belongs to
      belongs_to :mariadb_galera_cluster, optional: true

      def kind
        :mariadb
      end

      def components_needed
        ([:mariadb] + super).uniq
      end

      def service_status
        begin
          client = Mysql2::Client.new(host: guest.private_address, username: 'monitoring');
          result = client.query("SHOW STATUS");
          values = {}
          result.each do |e|
            values[e['Variable_name']] = e['Value']
          end
          client.close
          values
        rescue Exception => e
          return {key: :not_reachable, error: "Failed to get db status\n#{e.class}\n\n#{e.to_s}", severity: :critical}
        end
      end

      def backupable?
        true
      end

      def backup
        return false unless has_backups
        timestamp = Time.now.strftime "%Y%m%d%H%M%S"
        FileUtils.mkdir_p "#{backup_directory}/#{timestamp}"
        # `2>&1 >file`: the dump (stdout) goes to the file while stderr comes
        # back through the backticks — so auth failures are detectable here.
        command = "LC_ALL=C mysqldump -h #{guest.private_address.shellescape} -P #{port.to_i} -u backup --all-databases --all-tablespaces 2>&1 > #{backup_directory}/#{timestamp}/dump.sql"

        Rails.logger.debug command
        output = `#{command}`
        success = $?.success?

        if !success && output.match?(/access denied/i) && ensure_backup_user
          CloudModel.backup_log "mariadb: backup user was missing — created it, retrying dump"
          output = `#{command}`
          success = $?.success?
        end
        Rails.logger.debug output
        CloudModel.backup_log "mysqldump failed: #{output.strip.lines.last.to_s.strip}" unless success

        if success and File.exist? "#{backup_directory}/#{timestamp}/dump.sql"
          FileUtils.rm_f "#{backup_directory}/latest"
          FileUtils.ln_s "#{backup_directory}/#{timestamp}", "#{backup_directory}/latest"
          record_successful_backup
          cleanup_backups

          return true
        else
          FileUtils.rm_rf "#{backup_directory}/#{timestamp}"
          return false
        end
      end

      def restore timestamp='latest'
        # ToDo: mysql import data
      end

      # Read-only grants the dump user needs for `mysqldump --all-databases`.
      BACKUP_USER_GRANTS = 'SELECT, SHOW VIEW, TRIGGER, LOCK TABLES, PROCESS, EVENT'

      # (Re)create the passwordless `backup` user {#backup} connects with,
      # restricted to the private VPN /16 (same scheme as the `monitoring`
      # user). Older guests got this user by hand — creating it on demand via
      # the guest's local root socket lets backups self-heal when it is
      # missing (fresh deploys, restored databases).
      # @return [Boolean] whether the user is in place now
      def ensure_backup_user
        from = "#{guest.private_address.split('.').first(2).join('.')}.%"
        sql = "CREATE USER IF NOT EXISTS 'backup'@'#{from}'; " +
              "GRANT #{BACKUP_USER_GRANTS} ON *.* TO 'backup'@'#{from}'; " +
              "FLUSH PRIVILEGES;"
        success, out = guest.exec "mysql -e #{sql.shellescape}"
        Rails.logger.error "Could not ensure mariadb backup user on #{guest.name}: #{out}" unless success
        success
      end
    end
  end
end