module CloudModel
  module Components
    class RustComponent < BaseComponent
      def human_name
        "Rust #{version}".strip
      end

      def requirements
        [:clang]
      end
    end
  end
end
