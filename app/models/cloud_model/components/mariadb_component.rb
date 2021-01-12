module CloudModel
  module Components
    class MariadbComponent < BaseComponent
      def requirements
        [:mariadb_client]
      end
    end
  end
end