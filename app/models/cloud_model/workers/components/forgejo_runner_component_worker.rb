module CloudModel
  module Workers
    module Components
      # Component worker that installs the Forgejo Actions runner into a guest
      # template chroot.
      #
      # Installs git (jobs check out with it), the signature-checked
      # `forgejo-runner` release binary for the template's architecture, the
      # `forgejo-runner` system user with its work/cache directories and the
      # systemd unit. The {Services::ForgejoRunner} worker renders the config
      # with the instance connection at deploy time.
      class ForgejoRunnerComponentWorker < BaseComponentWorker
        # forgejo-runner release to install when the service does not pin one.
        FORGEJO_RUNNER_VERSION = "13.2.1".freeze

        def version
          @options[:component].try(:version).presence || FORGEJO_RUNNER_VERSION
        end

        def build build_path
          chroot! build_path, "apt-get install git git-lfs curl ca-certificates gnupg -y", "Failed to install runner tooling"

          chroot! build_path, "getent group forgejo-runner || addgroup --system forgejo-runner", "Failed to create forgejo-runner group"
          chroot! build_path, "getent passwd forgejo-runner || adduser --system --home /var/lib/forgejo-runner --shell /bin/bash --ingroup forgejo-runner --disabled-password --gecos 'Forgejo Runner' forgejo-runner", "Failed to create forgejo-runner user"
          chroot! build_path, "mkdir -p /etc/forgejo-runner /var/lib/forgejo-runner/cache /var/lib/forgejo-runner/work /var/lib/forgejo-runner/gems", "Failed to create forgejo-runner directories"
          chroot! build_path, "chown -R forgejo-runner:forgejo-runner /var/lib/forgejo-runner && chown root:forgejo-runner /etc/forgejo-runner && chmod 750 /etc/forgejo-runner", "Failed to set forgejo-runner permissions"

          url = "https://code.forgejo.org/forgejo/runner/releases/download/v#{version}/forgejo-runner-#{version}-linux-#{@template.arch}"
          chroot! build_path, "curl -fsSL #{url.shellescape} -o /tmp/forgejo-runner && curl -fsSL #{"#{url}.asc".shellescape} -o /tmp/forgejo-runner.asc", "Failed to download forgejo-runner #{version} (#{@template.arch})"
          ReleaseSignature.verify! self, build_path, ForgejoComponentWorker::FORGEJO_RELEASE_KEY, "/tmp/forgejo-runner", "forgejo-runner #{version}"
          chroot! build_path, "install -m 755 /tmp/forgejo-runner /usr/local/bin/forgejo-runner && rm -f /tmp/forgejo-runner /tmp/forgejo-runner.asc", "Failed to install forgejo-runner binary"
          chroot! build_path, "/usr/local/bin/forgejo-runner --version", "forgejo-runner binary not runnable"

          mkdir_p "#{build_path}/lib/systemd/system"
          render_to_remote "/cloud_model/guest/lib/systemd/system/forgejo_runner.service", "#{build_path}/lib/systemd/system/forgejo_runner.service"
        end
      end
    end
  end
end
