module CloudModel
  module Services
    class Neo4j < Base
      field :port, type: Integer, default: 7687

      def kind
        :neo4j
      end

      def components_needed
        ([:neo4j] + super).uniq
      end

      def service_status
        {}
      end

    end
  end
end