module CloudModel
  module Workers
    module Components
      class RubyComponentWorker < BaseComponentWorker
        def rubyversion
          @options[:component].try(:version) || CloudModel.config.ruby_version
        end

        def build build_path
          # Add RVM key
          chroot build_path, "gpg --keyserver hkp://keys.openpgp.org --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3 7D2BAF1CF37B13E2069D6956105BD0E739499BDB"

          # Install some packages needed for rails and curl needed for installing rvm
          packages = %w(git zlib1g-dev curl)
          if CloudModel.debian_name(@template.os_version) == 'Bionic Beaver'
            packages << 'bcrypt' # bcrypt @ Ubuntu 18.04
          else
            #packages << 'libcrypt1' # bcrypt @ Ubuntu 22.04, already seems to install automatically
          end
          packages << 'nodejs npm' # JS interpreter
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for deployment of rails app"

          # Install Yarn
          chroot! build_path, "npm install --global yarn", "Failed to install yarn"

          # Install RVM
          chroot! build_path, "curl -sSL https://get.rvm.io | bash -s master --ruby=ruby-#{rubyversion}", "Failed to install RVM"

          # Install bundler 1 and 2
          unless rubyversion =~ /\A2./
            # Do not install bundler > 1 on ruby 2.x
            chroot! build_path, "gem install bundler", "Failed to install current bundler"
          end
          chroot! build_path, "gem install bundler -v '~>1.0'", "Failed to install legacy bundler v1"

          # Remove installation files of RVM
          chroot! build_path, "rvm cleanup all", "Failed to cleanup rvm"

          # Stop gpg helpers to be able to umount dev after building
          chroot! build_path, "gpgconf --kill gpg-agent", "Failed to kill gpg agent"
          chroot! build_path, "gpgconf --kill dirmngr", "Failed to kill gpg dirmngr"
        end
      end
    end
  end
end