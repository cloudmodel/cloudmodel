module CloudModel
  module Workers
    module Components
      class RubyComponentWorker < BaseComponentWorker
        def build build_path
          packages = %w(ruby ruby-dev git)
          packages += %w(zlib1g-dev)
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