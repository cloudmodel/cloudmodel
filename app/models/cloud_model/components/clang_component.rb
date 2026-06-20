module CloudModel
  module Components
    class ClangComponent < BaseComponent
      def human_name
        "Clang/LLVM #{version}".strip
      end
    end
  end
end
