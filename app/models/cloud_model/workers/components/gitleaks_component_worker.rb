module CloudModel
  module Workers
    module Components
      # Component worker that installs the gitleaks release binary into a
      # guest template chroot. The tarball is verified against the SHA-256
      # the release publishes (pinned here per architecture) before the
      # binary is installed.
      class GitleaksComponentWorker < BaseComponentWorker
        # gitleaks release to install when the service does not pin one.
        GITLEAKS_VERSION = "8.30.1".freeze

        # SHA-256 of the release tarballs, from the release's checksums file.
        CHECKSUMS = {
          "8.30.1" => {
            "amd64" => "551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb",
            "arm64" => "e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080"
          }
        }.freeze

        def version
          @options[:component].try(:version).presence || GITLEAKS_VERSION
        end

        # gitleaks names the x86-64 tarball `x64`.
        def release_arch
          @template.arch == 'amd64' ? 'x64' : @template.arch
        end

        def build build_path
          checksum = CHECKSUMS.dig(version, @template.arch) or
            raise "No pinned checksum for gitleaks #{version} on #{@template.arch}; add it to GitleaksComponentWorker::CHECKSUMS"

          chroot! build_path, "apt-get install curl ca-certificates git -y", "Failed to install gitleaks prerequisites"
          url = "https://github.com/gitleaks/gitleaks/releases/download/v#{version}/gitleaks_#{version}_linux_#{release_arch}.tar.gz"
          chroot! build_path, "curl -fsSL #{url.shellescape} -o /tmp/gitleaks.tar.gz", "Failed to download gitleaks #{version} (#{@template.arch})"
          chroot! build_path, "echo #{"#{checksum}  /tmp/gitleaks.tar.gz".shellescape} | sha256sum -c --quiet -", "Checksum of gitleaks #{version} does not match the pinned value"
          chroot! build_path, "tar -xzf /tmp/gitleaks.tar.gz -C /tmp gitleaks && install -m 755 /tmp/gitleaks /usr/local/bin/gitleaks && rm -f /tmp/gitleaks /tmp/gitleaks.tar.gz", "Failed to install gitleaks binary"
          chroot! build_path, "/usr/local/bin/gitleaks version", "gitleaks binary not runnable"
        end
      end
    end
  end
end
