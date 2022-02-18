module CloudModel
  module Components
    class PhpImagemagickComponent < BaseComponent
      def human_name
        "PHP ImageMagick #{version}".strip
      end

      def requirements
        [:imagemagick, :php]
      end
    end
  end
end