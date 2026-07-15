module CloudModel
  module Workers
    module Components
      # Installs Node.js (from NodeSource) plus Yarn into a build template
      # chroot. Build-only tooling for compiling and bundling a web app's JS
      # assets; see {CloudModel::Components::NodejsComponent}.
      class NodejsComponentWorker < BaseComponentWorker
        def nodeversion
          @options[:component].try(:version) || '22'
        end

        def build build_path
          # Distro Node is usually too old for current app toolchains
          # (puppeteer/vite want a recent major), so pull it from NodeSource,
          # which also brings a matching npm.
          chroot! build_path, [
            "apt-get install -y ca-certificates curl gnupg",
            "curl -fsSL https://deb.nodesource.com/setup_#{nodeversion}.x | bash -",
            "apt-get install -y nodejs"
          ] * ' && ', "Failed to install Node.js"

          # Yarn on top of the NodeSource npm
          chroot! build_path, "npm install --global yarn", "Failed to install yarn"
        end
      end
    end
  end
end
