module CloudModel
  module Workers
    module Components
      class MongodbComponentWorker < BaseComponentWorker
        def mongoversion
          @options[:component].try(:version) || "6.0"
        end

        def build build_path
          chroot! build_path, "apt-get install gnupg -y", "Failed to install key management"
          chroot! build_path, "wget -q -O - https://www.mongodb.org/static/pgp/server-#{mongoversion}.asc | sudo apt-key add - ", "Failed to add mongodb key"


          chroot! build_path, "echo 'deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu #{CloudModel.debian_short_name(@template.os_version)}/mongodb-org/#{mongoversion} multiverse' | sudo tee /etc/apt/sources.list.d/mongodb-org-#{mongoversion}.list", "Failed to add mongodb to list if repos"
          chroot! build_path, "apt-get update", "Failed to update packages"

          if CloudModel.debian_name(@template.os_version) == 'Bionic Beaver'
            chroot! build_path, "apt-get install libreadline5 mongodb-org -y", "Failed to install mongodb"
          else
            chroot! build_path, "apt-get install mongodb-org -y", "Failed to install mongodb"
          end
        end
      end
    end
  end
end