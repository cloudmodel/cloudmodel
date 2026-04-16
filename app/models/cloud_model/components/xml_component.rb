module CloudModel
  module Components
    # Component that installs XML processing libraries (libxml2/libxslt) into a guest template.
    class XmlComponent < BaseComponent
      # @return [String] e.g. `"XML 2.9"`
      def human_name
        "XML #{version}".strip
      end
    end
  end
end