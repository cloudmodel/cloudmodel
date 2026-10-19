module CloudModel
  module Services
    # Neo4j graph database service embedded in a {Guest}.
    #
    # Runs a Neo4j instance and exposes the Bolt protocol port. Service status
    # is not actively probed (returns `{}`).
    class Neo4j < Base
      # @!attribute [rw] port
      #   @return [Integer] Neo4j Bolt protocol port (default: 7687)
      field :port, type: Integer, default: 7687

      def kind
        :neo4j
      end

      def components_needed
        ([:neo4j] + super).uniq
      end

      # Holds data: let it flush and close cleanly before the container is killed.
      def stop_timeout
        60
      end

      def service_status
        {}
      end

    end
  end
end