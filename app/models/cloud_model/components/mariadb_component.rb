module CloudModel
  module Components
    # Component that installs MariaDB server into a guest template.
    #
    # Declares a dependency on `:mariadb_client` so the client libraries are
    # always co-installed alongside the server.
    class MariadbComponent < BaseComponent
      # @return [String] e.g. `"MariaDB 10.11"`
      def human_name
        "MariaDB #{version}".strip
      end

      # @return [Array<Symbol>] `[:mariadb_client]`
      def requirements
        [:mariadb_client]
      end
    end
  end
end