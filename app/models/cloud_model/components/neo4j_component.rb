module CloudModel
  module Components
    class Neo4jComponent < BaseComponent
      def requirements
        [:java]
      end
    end
  end
end