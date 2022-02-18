module CloudModel
  module Components
    class MariadbComponent < BaseComponent
      def human_name
        "MariaDB #{version}".strip
      end

      def requirements
        [:mariadb_client]
      end
    end
  end
end