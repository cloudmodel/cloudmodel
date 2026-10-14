module CloudModel
  module Workers
    module Components
      class RustComponentWorker < BaseComponentWorker
        def rustversion
          @options[:component].try(:version) || 'stable'
        end

        def build build_path
          chroot! build_path, "CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | CARGO_HOME=/usr/local/cargo RUSTUP_HOME=/usr/local/rustup sh -s -- -y --default-toolchain #{rustversion} --no-modify-path", "Failed to install Rust toolchain"

          # The rustup proxies (cargo, rustc) only find the toolchain through
          # RUSTUP_HOME — without it they look in ~/.rustup and fail with
          # "no default configured". Export it for every login shell (chroot
          # commands source /etc/profile) and link the proxies into the
          # build root's PATH (not the host's).
          mkdir_p "#{build_path}/etc/profile.d"
          @host.exec! "printf '%s\\n' 'export CARGO_HOME=/usr/local/cargo' 'export RUSTUP_HOME=/usr/local/rustup' 'export PATH=/usr/local/cargo/bin:$PATH' > #{build_path.shellescape}/etc/profile.d/rust.sh && chmod 644 #{build_path.shellescape}/etc/profile.d/rust.sh",
            'Failed to write the Rust environment'
          chroot! build_path, "ln -sf /usr/local/cargo/bin/cargo /usr/local/bin/cargo && ln -sf /usr/local/cargo/bin/rustc /usr/local/bin/rustc && ln -sfn /usr/local/rustup /root/.rustup && ln -sfn /usr/local/cargo /root/.cargo",
            'Failed to link the Rust toolchain'
        end
      end
    end
  end
end
