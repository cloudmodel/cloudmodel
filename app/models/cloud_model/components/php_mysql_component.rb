module CloudModel
  module Components
    class PhpMysqlComponent < BaseComponent
      def requirements
        [:mariadb_client, :php]
      end
    end
  end
end