module CloudModel
  module Components
    class LibfcgiComponent < BaseComponent
      def human_name
        "libFCGI #{version}".strip
      end
    end
  end
end