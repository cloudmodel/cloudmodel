require 'mysql2'

module CloudModel
  module Services
    class Mariadb < Base
      field :port, type: Integer, default: 3306
      field :mariadb_galera_port, type: Integer, default: 4567
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
        command = "LC_ALL=C mysqldump -h #{guest.private_address} -P #{port} -u backup --all-databases --all-tablespaces > #{backup_directory}/#{timestamp}/dump.sql"

        Rails.logger.debug command
        Rails.logger.debug `#{command}`

        if $?.success? and File.exists? "#{backup_directory}/#{timestamp}/dump.sql"
          FileUtils.rm_f "#{backup_directory}/latest"
          FileUtils.ln_s "#{backup_directory}/#{timestamp}", "#{backup_directory}/latest"
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
    end
  end
end