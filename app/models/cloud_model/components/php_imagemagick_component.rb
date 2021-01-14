module CloudModel
  module Components
    class PhpImagemagickComponent < BaseComponent
      def requirements
        [:imagemagick, :php]
      end
    end
  end
end