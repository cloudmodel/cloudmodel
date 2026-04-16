module CloudModel
  module Components
    # Component that installs the PHP ImageMagick extension into a guest template.
    #
    # Requires both `:imagemagick` and `:php` components.
    class PhpImagemagickComponent < BaseComponent
      # @return [String] e.g. `"PHP ImageMagick"`
      def human_name
        "PHP ImageMagick #{version}".strip
      end

      # @return [Array<Symbol>] `[:imagemagick, :php]`
      def requirements
        [:imagemagick, :php]
      end
    end
  end
end