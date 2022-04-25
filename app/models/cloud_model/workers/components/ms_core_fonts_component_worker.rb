module CloudModel
  module Workers
    module Components
      class MsCoreFontsComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | sudo debconf-set-selections", "Failed to accept MS Core Fonts Licence"
          chroot! build_path, "apt-get install ttf-mscorefonts-installer", "Failed to install MS Core Fonts"
        end
      end
    end
  end
end