module CloudModel
  module Components
    class PhpMysqlComponent < BaseComponent
      def human_name
        "PHP MySQL #{version}".strip
      end

      def requirements
        [:mariadb_client, :php]
      end
    end
  end
end