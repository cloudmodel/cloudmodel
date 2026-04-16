module CloudModel
  module Components
    # Component that installs the MariaDB client libraries into a guest template.
    #
    # Used as a dependency by {MariadbComponent} and {PhpMysqlComponent}.
    class MariadbClientComponent < BaseComponent
      # @return [String] e.g. `"MariaDB Client 10.11"`
      def human_name
        "MariaDB Client #{version}".strip
      end
    end
  end
end