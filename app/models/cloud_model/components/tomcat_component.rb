module CloudModel
  module Components
    # Component that installs Apache Tomcat into a guest template.
    #
    # Declares a dependency on the `:java` component, which must be installed first.
    class TomcatComponent < BaseComponent
      # @return [Array<Symbol>] `[:java]`
      def requirements
        [:java]
      end
    end
  end
end