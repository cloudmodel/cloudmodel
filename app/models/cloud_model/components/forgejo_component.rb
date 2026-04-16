module CloudModel
  module Components
    # Component that installs Forgejo into a guest template.
    class ForgejoComponent < BaseComponent
      # @return [Symbol] always `:forgejo`
      def name
        :forgejo
      end
    end
  end
end