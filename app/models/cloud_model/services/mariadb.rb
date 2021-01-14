module CloudModel
  module Services
    class Mariadb < Base
      field :port, type: Integer, default: 3306

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