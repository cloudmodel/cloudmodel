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
        # ToDo: mysql dump data
      end

      def restore timestamp='latest'
        # ToDo: mysql import data
      end
    end
  end
end