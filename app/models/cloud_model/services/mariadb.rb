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