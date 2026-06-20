module CloudModel
  module Workers
    module Components
      class ClangComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install clang llvm-dev libclang-dev -y", "Failed to install LLVM/Clang"
        end
      end
    end
  end
end
