module CloudModel
  module Components
    # Component that installs the PHP MySQL/MariaDB extension into a guest template.
    #
    # Requires both `:mariadb_client` and `:php` components.
    class PhpMysqlComponent < BaseComponent
      # @return [String] e.g. `"PHP MySQL"`
      def human_name
        "PHP MySQL #{version}".strip
      end

      # @return [Array<Symbol>] `[:mariadb_client, :php]`
      def requirements
        [:mariadb_client, :php]
      end
    end
  end
end