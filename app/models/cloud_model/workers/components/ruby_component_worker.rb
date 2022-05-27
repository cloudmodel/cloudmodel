module CloudModel
  module Workers
    module Components
      class RubyComponentWorker < BaseComponentWorker
        def rubyversion
          @options[:component].try(:version) || CloudModel.config.ruby_version
        end

        def build build_path
          chroot build_path, "gpg --keyserver hkp://keys.openpgp.org --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB"
          packages = %w(git zlib1g-dev curl)
          packages << 'bcrypt' # bcrypt
          packages << 'nodejs' # JS interpreter
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for deployment of rails app"

          chroot! build_path, "curl -sSL https://get.rvm.io | bash -s master --ruby=ruby-#{rubyversion}", "Failed to install RVM"

          # chroot! build_path, 'echo "source /usr/local/rvm/scripts/rvm" >> /etc/profile', "Failed to add RVM to profile"

          # * To start using RVM you need to run `source /usr/local/rvm/scripts/rvm`
         #    in all your open shell windows, in rare cases you need to reopen all shell windows.

          # # This approach ends with ruby 2.7 as brightbox seems to be inactive
          # chroot! build_path, "add-apt-repository ppa:brightbox/ruby-ng -y", "Failed to add ruby-ng ppa"
          # chroot! build_path, "apt-get update", "Failed to update apt"
          #
          # packages = ["ruby#{rubyversion}", "ruby#{rubyversion}-dev"]
          # packages += %w(ruby-switch git zlib1g-dev)
          # packages << 'ruby-bcrypt' # bcrypt
          # packages << 'nodejs' # JS interpreter
          # chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for deployment of rails app"

          chroot! build_path, "gem install bundler", "Failed to install current bundler"
          chroot! build_path, "gem install bundler -v '~>1.0'", "Failed to install legacy bundler v1"
        end
      end
    end
  end
end