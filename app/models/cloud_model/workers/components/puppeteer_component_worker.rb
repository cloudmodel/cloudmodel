module CloudModel
  module Workers
    module Components
      # Installs the distribution Chromium package (Node itself comes from the
      # required NodejsComponent). grover/Puppeteer are pointed at /usr/bin/chromium
      # instead of downloading a browser: the download has no arm64 Linux build,
      # and the distro package is the maintained, security-patched Chromium for
      # both architectures and pulls in its own shared-library dependencies.
      # See {CloudModel::Components::PuppeteerComponent}.
      class PuppeteerComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install chromium -y", "Failed to install Chromium"
        end
      end
    end
  end
end
