module CloudModel
  module Components
    # Component that installs Collabora Online (CODE) into a guest template.
    class CollaboraComponent < BaseComponent
      # @return [Array<Symbol>] no additional component requirements
      def requirements
        []
      end
    end
  end
end