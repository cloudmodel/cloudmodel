module CloudModel
  module Components
    # Component that installs Apache Jena Fuseki into a guest template.
    #
    # Requires Java 17 as a dependency.
    class FusekiComponent < BaseComponent
      # @return [Array<Symbol>] `[:"java@17"]`
      def requirements
        [:'java@17']
      end
    end
  end
end