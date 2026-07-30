module CloudModel
  module Workers
    module Components
      # Component worker that installs Forgejo into a guest template chroot.
      #
      # Installs the base git tooling (`git`, `git-lfs`) from the distribution
      # and the Forgejo server from the official release binary. The upstream
      # `forgejo-contrib` Debian repository only publishes `amd64` packages, so
      # a binary install is used for every architecture to keep amd64 and arm64
      # on the exact same version. The `forgejo` system user, data directories
      # and the systemd unit are created here so the {Services::Forgejo} worker
      # only has to render `app.ini`, the branding and (optionally) the OIDC
      # login source at deploy time.
      class ForgejoComponentWorker < BaseComponentWorker
        # Forgejo release to install (current LTS line). Bump to roll forward.
        FORGEJO_VERSION = "11.0.16".freeze

        def version
          @options[:component].try(:version).presence || FORGEJO_VERSION
        end

        def build build_path
          chroot! build_path, "apt-get install git git-lfs curl ca-certificates -y", "Failed to install git tooling"

          # Dedicated system user + data/config layout (mirrors the deb package).
          chroot! build_path, "getent group forgejo || addgroup --system forgejo", "Failed to create forgejo group"
          chroot! build_path, "getent passwd forgejo || adduser --system --home /var/lib/forgejo --shell /bin/bash --ingroup forgejo --disabled-password --gecos 'Forgejo' forgejo", "Failed to create forgejo user"
          chroot! build_path, "mkdir -p /etc/forgejo /var/lib/forgejo/custom/public/assets/img /var/lib/forgejo/data /var/lib/forgejo/log", "Failed to create forgejo directories"
          chroot! build_path, "chown -R forgejo:forgejo /var/lib/forgejo && chown root:forgejo /etc/forgejo && chmod 770 /etc/forgejo", "Failed to set forgejo permissions"

          # Forgejo server binary for this template's architecture.
          url = "https://codeberg.org/forgejo/forgejo/releases/download/v#{version}/forgejo-#{version}-linux-#{@template.arch}"
          chroot! build_path, "curl -fsSL #{url.shellescape} -o /usr/bin/forgejo && chmod 755 /usr/bin/forgejo", "Failed to download forgejo #{version} (#{@template.arch})"
          chroot! build_path, "/usr/bin/forgejo --version", "Forgejo binary not runnable"

          # systemd unit (the Services::Forgejo worker adds the fix_perms drop-in).
          mkdir_p "#{build_path}/lib/systemd/system"
          render_to_remote "/cloud_model/guest/lib/systemd/system/forgejo.service", "#{build_path}/lib/systemd/system/forgejo.service"
        end
      end
    end
  end
end
