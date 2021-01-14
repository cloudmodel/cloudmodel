module CloudModel
  module Workers
    module Components
      class RubyComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "add-apt-repository ppa:brightbox/ruby-ng -y", "Failed to add ruby-ng ppa"
          chroot! build_path, "apt-get update", "Failed to update apt"

          packages = ["ruby-#{CloudModel.config.ruby_version}", "ruby-dev-#{CloudModel.config.ruby_version}"]
          packages += %w(ruby-switch git zlib1g-dev)
          packages << 'ruby-bcrypt' # bcrypt
          packages << 'nodejs' # JS interpreter
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for deployment of rails app"
          chroot! build_path, "gem install bundler", "Failed to install current bundler"
          chroot! build_path, "gem install bundler -v '~>1.0'", "Failed to install legacy bundler v1"
        end
      end
    end
  end
end