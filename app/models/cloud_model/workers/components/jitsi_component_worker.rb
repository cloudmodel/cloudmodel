module CloudModel
  module Workers
    module Components
      # Component worker that installs the Jitsi Meet stack into a guest template chroot.
      #
      # Adds the Prosody and Jitsi apt repositories and installs the full Jitsi
      # Meet stack (Videobridge, Jicofo, Prosody, web + web-config) via the
      # `jitsi-meet` metapackage. The install is debconf-driven (it bakes in a
      # hostname), so a placeholder domain is used at template-build time; the
      # {Services::Jitsi} worker re-points the stack at the guest's real hostname
      # and applies branding at deploy time.
      class JitsiComponentWorker < BaseComponentWorker
        # Placeholder hostname baked into the template; re-pointed at deploy.
        BUILD_HOSTNAME = "meet.build.local".freeze

        def build build_path
          chroot! build_path, "apt-get install -y curl gnupg debconf-utils lsb-release", "Failed to install prerequisites"

          # Prosody repo (matches the base OS codename)
          chroot! build_path, "curl -sL https://prosody.im/files/prosody-debian-packages.key -o /etc/apt/keyrings/prosody-debian-packages.key", "Failed to add prosody key"
          chroot! build_path, "echo \"deb [signed-by=/etc/apt/keyrings/prosody-debian-packages.key] http://packages.prosody.im/debian $(lsb_release -sc) main\" | tee /etc/apt/sources.list.d/prosody-debian-packages.list", "Failed to add prosody source"

          # Jitsi stable repo
          chroot! build_path, "curl -sL https://download.jitsi.org/jitsi-key.gpg.key | sh -c 'gpg --dearmor > /usr/share/keyrings/jitsi-keyring.gpg'", "Failed to add jitsi key"
          chroot! build_path, "echo \"deb [signed-by=/usr/share/keyrings/jitsi-keyring.gpg] https://download.jitsi.org stable/\" | tee /etc/apt/sources.list.d/jitsi-stable.list", "Failed to add jitsi source"

          chroot! build_path, "apt-get update", "Failed to update packages"
          chroot! build_path, "apt-get install -y lua5.2", "Failed to install lua 5.2"

          # Non-interactive jitsi-meet install: preseed the debconf hostname and
          # self-signed cert choice (cloudmodel manages the real TLS cert on the
          # nginx side), then pull the metapackage (jvb2, jicofo, prosody, web).
          chroot! build_path, "echo 'jitsi-videobridge2 jitsi-videobridge/jvb-hostname string #{BUILD_HOSTNAME}' | debconf-set-selections", "Failed to preseed jvb hostname"
          chroot! build_path, "echo 'jitsi-meet-web-config jitsi-meet/cert-choice select Generate a new self-signed certificate (You will later get a chance to obtain a Let'\\''s encrypt certificate)' | debconf-set-selections", "Failed to preseed cert choice"
          chroot! build_path, "DEBIAN_FRONTEND=noninteractive apt-get install -y jitsi-meet", "Failed to install jitsi-meet"
        end
      end
    end
  end
end
