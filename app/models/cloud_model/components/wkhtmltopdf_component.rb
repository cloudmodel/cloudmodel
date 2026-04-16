module CloudModel
  module Components
    # Component that installs wkhtmltopdf into a guest template.
    #
    # Provides HTML-to-PDF rendering via WebKit.
    class WkhtmltopdfComponent < BaseComponent
      # @return [String] e.g. `"wkhtmltopdf 0.12.6"`
      def human_name
        "wkhtmltopdf #{version}".strip
      end
    end
  end
end