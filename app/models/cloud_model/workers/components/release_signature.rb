module CloudModel
  module Workers
    module Components
      # Verifies a downloaded release asset against its detached OpenPGP
      # signature inside a template build chroot.
      #
      # The signing key is fetched by fingerprint from keys.openpgp.org (plain
      # HTTPS, no dirmngr/keyserver protocol needed inside the chroot) and
      # imported into the chroot's root keyring; the verification pins the
      # expected fingerprint so a wrong or missing key fails the build. The gpg
      # helper daemons are stopped afterwards so the chroot can be unmounted.
      module ReleaseSignature
        KEYSERVER = "https://keys.openpgp.org/vks/v1/by-fingerprint".freeze

        # @param worker [BaseComponentWorker] worker whose chroot! runs the commands
        # @param build_path [String] template chroot
        # @param fingerprint [String] 40 hex chars of the signing key
        # @param file [String] downloaded asset inside the chroot; `<file>.asc` is its signature
        # @param label [String] what is being verified, for error messages
        # @raise [RuntimeError] when the key cannot be imported or the signature does not verify
        def self.verify! worker, build_path, fingerprint, file, label
          worker.chroot! build_path, "curl -fsSL #{"#{KEYSERVER}/#{fingerprint}".shellescape} | gpg --batch --no-tty --import", "Failed to import release key #{fingerprint} for #{label}"
          # VALIDSIG names the signing subkey first and ends with the primary
          # key fingerprint — that is the one pinned here.
          worker.chroot! build_path, "gpg --batch --no-tty --status-fd 1 --verify #{"#{file}.asc".shellescape} #{file.shellescape} | grep -qE #{"^\\[GNUPG:\\] VALIDSIG .* #{fingerprint}$".shellescape}", "Release signature of #{label} does not verify against #{fingerprint}"
          worker.chroot build_path, "gpgconf --kill all"
        end
      end
    end
  end
end
