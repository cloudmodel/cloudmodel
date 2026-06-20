module CloudModel
  module Workers
    module Components
      class RustComponentWorker < BaseComponentWorker
        def rustversion
          @options[:component].try(:version) || 'stable'
        end

        def build build_path
          chroot! build_path, "CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup sh -s -- -y --default-toolchain #{rustversion} --no-modify-path", "Failed to install Rust toolchain"

          mkdir_p "#{build_path}/etc/profile.d"
          @host.exec "echo 'export PATH=/usr/local/cargo/bin:$PATH' > #{build_path.shellescape}/etc/profile.d/rust.sh"
          @host.exec "chmod 644 #{build_path.shellescape}/etc/profile.d/rust.sh"
          @host.exec "ln -sf /usr/local/cargo/bin/cargo /usr/local/bin/cargo"
          @host.exec "ln -sf /usr/local/cargo/bin/rustc /usr/local/bin/rustc"
        end
      end
    end
  end
end
