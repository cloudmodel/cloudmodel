module CloudModel
  module Workers
    module Components
      class ForgejoComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "wget --content-disposition https://code.forgejo.org/forgejo-contrib/-/packages/debian/forgejo-deb-repo/0-0/files/2890", "Failed to get Forgejo apt repo"
          chroot! build_path, "apt-get install ./forgejo-deb-repo_0-0_all.deb", "Failed to install forgejo apt repo"
          chroot! build_path, "apt-get update", "Failed to update packages"
          chroot! build_path, "apt-get install git git-lfs forgejo-bin -y", "Failed to install forgejo"
        end
      end
    end
  end
end
