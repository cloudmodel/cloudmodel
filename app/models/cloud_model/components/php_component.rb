module CloudModel
  module Components
    # Component that installs PHP-FPM into a guest template.
    class PhpComponent < BaseComponent
      def human_name
        "PHP #{version}".strip
      end
    end
  end
end