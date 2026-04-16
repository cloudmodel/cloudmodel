module CloudModel
  module Components
    # Component that installs Neo4j into a guest template.
    #
    # Requires the `:java` component as a dependency.
    class Neo4jComponent < BaseComponent
      # @return [Array<Symbol>] `[:java]`
      def requirements
        [:java]
      end
    end
  end
end