module CloudModel
  module Workers
    module Components
      class CollaboraComponentWorker < BaseComponentWorker
        def _prepare_collabora_repository build_path
          chroot! build_path, "apt-get install dirmngr gnupg -y", "Failed to install key management"
          chroot! build_path, "echo 'deb https://www.collaboraoffice.com/repos/CollaboraOnline/CODE-ubuntu1804 ./' | sudo tee /etc/apt/sources.list.d/collabora.list", "Failed to add collabora to list if repos"
          chroot! build_path, "apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 0C54D189F4BA284D", "Failed to add collabora key"
        end


        def build build_path
          ### TODO; Test build in collabora
          ### if running: remove /cloud_model/guest/etc/apt/sources.list.d/collabora.list
          ### if not running: fix sources
          _prepare_collabora_repository build_path

          chroot! build_path, "apt-get update", "Failed to update packages"
          if CloudModel.debian_name(@template.os_version) == 'Bionic Beaver'
            chroot! build_path, "apt-get install apt-transport-https ca-certificates loolwsd code-brand -y", "Failed to install collabora"
          else
            chroot! build_path, "apt-get install apt-transport-https ca-certificates coolwsd code-brand -y", "Failed to install collabora"
          end
        end
      end
    end
  end
end

# loolconfig set ssl.enable false
# loolconfig set ssl.termination true
# loolconfig set storage.wopi.host nextcloud.example.com