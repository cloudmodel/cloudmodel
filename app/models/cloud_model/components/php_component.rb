module CloudModel
  module Components
    class PhpComponent < BaseComponent
      def human_name
        "PHP #{version}".strip
      end
    end
  end
end