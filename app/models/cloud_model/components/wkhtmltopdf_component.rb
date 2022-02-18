module CloudModel
  module Components
    class WkhtmltopdfComponent < BaseComponent
      def human_name
        "wkhtmltopdf #{version}".strip
      end
    end
  end
end