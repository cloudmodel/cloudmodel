module CloudModel
  module Components
    class ImagemagickComponent < BaseComponent
      def human_name
        "ImageMagick #{version}".strip
      end
    end
  end
end