module CloudModel
  module Components
    # Component that installs ImageMagick into a guest template.
    class ImagemagickComponent < BaseComponent
      # @return [String] e.g. `"ImageMagick 7"`
      def human_name
        "ImageMagick #{version}".strip
      end
    end
  end
end