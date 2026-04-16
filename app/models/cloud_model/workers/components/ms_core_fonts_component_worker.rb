module CloudModel
  module Workers
    module Components
      # Component worker that installs Microsoft Core Fonts into a guest template chroot.
      #
      # Pre-seeds `debconf` to accept the EULA automatically, then installs
      # `ttf-mscorefonts-installer`.
      class MsCoreFontsComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections", "Failed to accept MS Core Fonts Licence"
          chroot! build_path, "apt-get install ttf-mscorefonts-installer", "Failed to install MS Core Fonts"
        end
      end
    end
  end
end