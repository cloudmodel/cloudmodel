module CloudModel
  module Workers
    module Components
      # Component worker for guests that run Ruby. It installs no Ruby: the
      # releases come read-only from the host's per-(os, arch) dataset
      # ({CloudModel::RubyRelease}), the template gets the shims and the
      # default symlink from {Mixins::RubyLayout} (GuestTemplateWorker), the
      # guest its lines at deploy (GuestWorker#ensure_ruby). What the
      # template needs are the shared libraries the interpreter links
      # against and the headers native gems compile against, plus git and
      # curl for bundler. Node/Yarn live in {NodejsComponentWorker}
      # (build-only), the Puppeteer/Chromium runtime libs in
      # {PuppeteerComponentWorker} (opt-in), so a plain Rails runtime stays
      # lean.
      class RubyComponentWorker < BaseComponentWorker
        PACKAGES = %w(git curl ca-certificates build-essential libssl-dev libyaml-dev zlib1g-dev libffi-dev libreadline-dev libgdbm-dev libgmp-dev).freeze

        def build build_path
          packages = PACKAGES.dup
          packages << 'bcrypt' if CloudModel.debian_name(@template.os_version) == 'Bionic Beaver' # bcrypt @ Ubuntu 18.04
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install the Ruby runtime libraries and build dependencies"
        end
      end
    end
  end
end
