module CloudModel
  module Workers
    module Components
      # Component worker that installs the Fleet server and `fleetctl` into a
      # guest template chroot.
      #
      # Fleet publishes no apt repository; the release tarballs are downloaded
      # from GitHub and checked against the release's `checksums.txt` (Fleet
      # does not sign its release assets with OpenPGP). The server is only
      # built for amd64; `fleetctl` exists for amd64 and arm64. The `fleet`
      # system user, its directories and the systemd unit are created here so
      # the {Services::Fleet} worker only has to render the configuration.
      class FleetComponentWorker < BaseComponentWorker
        # Fleet release installed when the service does not pin one.
        FLEET_VERSION = "4.96.0".freeze

        # Architectures Fleet publishes a server binary for.
        SERVER_ARCHES = %w[amd64].freeze

        RELEASES = "https://github.com/fleetdm/fleet/releases/download".freeze

        def version
          @options[:component].try(:version).presence || FLEET_VERSION
        end

        def build build_path
          unless SERVER_ARCHES.include? @template.arch
            raise "Fleet #{version} publishes its server for #{SERVER_ARCHES.join(', ')} only, not for #{@template.arch}"
          end

          chroot! build_path, "apt-get install curl ca-certificates -y", "Failed to install download tooling"

          chroot! build_path, "getent group fleet || addgroup --system fleet", "Failed to create fleet group"
          chroot! build_path, "getent passwd fleet || adduser --system --home /var/lib/fleet --shell /usr/sbin/nologin --ingroup fleet --disabled-password --gecos 'Fleet' fleet", "Failed to create fleet user"
          chroot! build_path, "mkdir -p /etc/fleet /var/lib/fleet /var/log/fleet && chown -R fleet:fleet /var/lib/fleet /var/log/fleet && chown root:fleet /etc/fleet && chmod 750 /etc/fleet", "Failed to create fleet directories"

          base = "#{RELEASES}/fleet-v#{version}"
          server = "fleet_v#{version}_linux"
          cli = "fleetctl_v#{version}_linux_#{@template.arch}"

          chroot! build_path, "mkdir -p /tmp/fleet && cd /tmp/fleet && curl -fsSL #{"#{base}/checksums.txt".shellescape} -o checksums.txt && curl -fsSL #{"#{base}/#{server}.tar.gz".shellescape} -o #{server}.tar.gz && curl -fsSL #{"#{base}/#{cli}.tar.gz".shellescape} -o #{cli}.tar.gz", "Failed to download fleet #{version} (#{@template.arch})"
          [server, cli].each do |asset|
            chroot! build_path, "cd /tmp/fleet && grep -E #{"  #{Regexp.escape asset}\\.tar\\.gz$".shellescape} checksums.txt | sha256sum -c --strict -", "Checksum of #{asset}.tar.gz does not match the release's checksums.txt"
          end
          chroot! build_path, "cd /tmp/fleet && tar xzf #{server}.tar.gz && tar xzf #{cli}.tar.gz && install -m 755 #{server}/fleet /usr/bin/fleet && install -m 755 #{cli}/fleetctl /usr/bin/fleetctl && cd / && rm -rf /tmp/fleet", "Failed to install fleet binaries"
          chroot! build_path, "/usr/bin/fleet version && /usr/bin/fleetctl --version", "Fleet binaries not runnable"

          mkdir_p "#{build_path}/lib/systemd/system"
          render_to_remote "/cloud_model/guest/lib/systemd/system/fleet.service", "#{build_path}/lib/systemd/system/fleet.service"
        end
      end
    end
  end
end
