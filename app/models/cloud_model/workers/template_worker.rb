module CloudModel
  module Workers
    class TemplateWorker < BaseWorker
      def download_path
        "/cloud/build/downloads/"
      end

      def error_log_object
        @template
      end

      def os_version
        @template.os_version
      end

      def ubuntu_version
        @template.os_version.gsub(/^ubuntu-/, '')
      end

      def ubuntu_kernel_flavour
        CloudModel.config.ubuntu_kernel_flavour
      end

      def ubuntu_arch
        @template.arch
      end

      def ubuntu_image
        "ubuntu-base-#{ubuntu_version}-base-#{ubuntu_arch}.tar.gz"
      end

      def ubuntu_url
        if(ubuntu_version =~ /-beta/)
          version = ubuntu_version.split('-')
          "http://cdimage.ubuntu.com/ubuntu-base/releases/#{version[0]}/#{version[1].gsub('beta', 'beta-')}/#{ubuntu_image}"
        else
          "http://cdimage.ubuntu.com/ubuntu-base/releases/#{ubuntu_version}/release/#{ubuntu_image}"
        end
      end

      def fetch_ubuntu
        begin
          @host.sftp.stat!("#{download_path}#{ubuntu_image}")
        rescue
          comment_sub_step "Downloading #{ubuntu_url}"
          @host.exec! "cd #{download_path} && curl #{ubuntu_url.shellescape} -o #{download_path}#{ubuntu_image}", "Failed to download ubuntu image"
        end
      end

      def debootstrap_debian

        # gettting the key does not work for now; apt debian-keyring debian-archive-keyring is to old on ubuntu 18.04

        @host.exec! "apt-get install debootstrap  -y", "Failed to install debootstrap"
        @host.exec "debootstrap --arch #{@template.arch} bookworm #{build_path} http://ftp.de.debian.org/debian/"#, "Failed to debootstrap"

        # debootstrap --arch amd64 bookworm /cloud/build/host/test http://ftp.de.debian.org/debian/

        # Copy resolv.conf
        @host.exec! "cp /etc/resolv.conf #{build_path}/etc", "Failed to copy resolve conf"

        # Don't start services on install
        # render_to_remote "/cloud_model/support/usr/sbin/policy-rc.d", "#{build_path}/usr/sbin/policy-rc.d", 0755
        # Don't install docs
        render_to_remote  "/cloud_model/support/etc/dpkg/dpkg.cfg.d/01_nodoc", "#{build_path}/etc/dpkg/dpkg.cfg.d/01_nodoc"

        chroot! build_path, "apt-get install software-properties-common -y", "Failed to update sources"
        chroot! build_path, "apt-add-repository contrib -y", "Failed to update sources"


        # apt-get install debootstrap
        # debootstrap --arch amd64 testing /cloud/build/host/test http://ftp.de.debian.org/debian/
        # debootstrap --arch amd64 bookworm /cloud/build/host/test http://ftp.de.debian.org/debian/
        # LANG=C.UTF-8 chroot /cloud/build/host/test /bin/bash

        # apt install makedev
        # mount none /proc -t proc
        # cd /dev
        # MAKEDEV generic

        ## ZFS

        # apt-get install software-properties-common -y
        # apt-add-repository contrib -y
        # apt-get install zfsutils-linux -y


        ## TODO Change kernel install

        # apt-get install linux-image-cloud-amd64 -y
      end

      def populate_root
        @host.exec! "cd #{build_path} && tar xzpf #{download_path}#{ubuntu_image}", "Failed to unpack system image!"
        # Copy resolv.conf
        @host.exec! "cp /etc/resolv.conf #{build_path}/etc", "Failed to copy resolve conf"
        # Enable universe sources
        @host.exec! "sed -i \"/^# deb.*universe/ s/^# //\" #{build_path}/etc/apt/sources.list", "Failed to activate universe sources"
        @host.exec! "sed -i \"s*http://archive.ubuntu.com/ubuntu/*#{CloudModel.config.ubuntu_mirror}*\" #{build_path}/etc/apt/sources.list", "Failed to set ubutu mirror"
        @host.exec! "sed -i \"s*http://security.ubuntu.com/ubuntu/*#{CloudModel.config.ubuntu_mirror}*\" #{build_path}/etc/apt/sources.list", "Failed to set ubutu security mirror"
        @host.exec! "sed -i \"s/^deb-src/# deb-src/\" #{build_path}/etc/apt/sources.list", "Failed to set disable deb-src" unless CloudModel.config.ubuntu_deb_src
        # Don't start services on install
        render_to_remote "/cloud_model/support/usr/sbin/policy-rc.d", "#{build_path}/usr/sbin/policy-rc.d", 0755
        # Don't install docs
        render_to_remote  "/cloud_model/support/etc/dpkg/dpkg.cfg.d/01_nodoc", "#{build_path}/etc/dpkg/dpkg.cfg.d/01_nodoc"
      end

      def update_base
        chroot! build_path, "dpkg --configure -a && apt-get update && apt-get upgrade -y", "Failed to update sources"
        # # Set locale
        # chroot! build_path, "apt-get install console-setup-linux -y",  "Failed to install console setup"
        # chroot! build_path, "localedef -i en_US -c -f UTF-8 en_US.UTF-8", "Failed to define locale"
        # chroot! build_path, "update-locale LANG=en_US.UTF-8 LC_MESSAGES=POSIX", "Failed to update locale"
      end

      def install_ssh
        chroot! build_path, "apt-get install ssh -y", "Failed to install SSH"
        # SSH is enabled by default, do no need to enable it by hand
      end


      def tar_template build_path, template
        mkdir_p File.dirname(template.tarball)
        build_tar '.', template.tarball, one_file_system: true, exclude: [
          './tmp/*',
          './run/*',
          './var/tmp/*',
          './var/run/*',
          './var/cache/*',
          './usr/share/man',
          './usr/share/doc',
          './etc/ssh/*_key*'
        ], C: build_path
      end

      def download_new_template
        @template.update_attribute :build_state, :downloading
        download_template @template
      end

      def finalize_template
        @template.update_attribute :build_state, :finished
        cleanup_chroot build_path
        @host.exec "rm -rf #{build_path.shellescape}"
      end

    end
  end
end