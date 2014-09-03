require 'fileutils'
require 'net/http'
require 'net/sftp'
require 'securerandom'

module CloudModel
  module Images
    class BaseWorker < CloudModel::BaseWorker
      def check_config
        unless CloudModel.config.gentoo_mirrors
          raise "You need to configure at least one gentoo_mirror in CloudModel.config.gentoo_mirrors"
        end
        true
      end
    
      def build_dir
        "/vm/build/#{build_type}"
      end
    
      def prepare_build_dir
        unmount_build_dir

        #
        # Create and mount build root if necessary
        #
        unless @host.mounted_at? build_dir
          # puts "    Create build host partition"
          begin
            build_lv = CloudModel::LogicalVolume.find_by(name: "build-#{build_type}")
            build_lv.apply wipe: true
          rescue
            build_lv = CloudModel::LogicalVolume.create! name: "build-#{build_type}", disk_space: "32G", volume_group: @host.volume_groups.first
          end

          unless build_lv.mount build_dir
            raise 'Failed to mount build partition'
          end
        end

        # # Mount boot device
        # unless @host.mount_boot_fs build_dir
        #   raise "Failed to mount /boot to build system"
        # end
      end

      def unmount_build_dir
        cleanup_chroot build_dir
        if @host.mounted_at? build_dir
          @host.exec! "umount #{build_dir}", 'Failed to unmount build root device'
        end
      end
    
      def download_stage3
        # Find latest stage 3 image on gentoo mirror
        gentoo_release_path = 'releases/amd64/autobuilds/'
        gentoo_stage3_info = 'latest-stage3-amd64-hardened+nomultilib.txt'
        gentoo_stage3_file = Net::HTTP.get(URI.parse("#{CloudModel.config.gentoo_mirrors.first}#{gentoo_release_path}#{gentoo_stage3_info}")).lines.last.strip.shellescape

        # Download and unpack stage 3
        @host.exec! "curl #{CloudModel.config.gentoo_mirrors.first}#{gentoo_release_path}#{gentoo_stage3_file} -o #{build_dir}/stage3.tar.bz2", 'Could not load stage 3 file'
      end

      def unpack_stage3
        # TODO: Check checksum of stage3 file
        @host.exec! "cd #{build_dir} && tar xjpf stage3.tar.bz2", 'Failed to unpack stage 3 file'
      end

      def remove_stage3
        @host.ssh_connection.sftp.remove! "#{build_dir}/stage3.tar.bz2"
      end
    
      def configure_build_system
        render_to_remote "/cloud_model/#{build_type}/etc/portage/make.conf", "#{build_dir}/etc/portage/make.conf", 0600, mirrors: CloudModel.config.gentoo_mirrors, host: @host
        render_to_remote "/cloud_model/#{build_type}/etc/portage/package.accept_keywords", "#{build_dir}/etc/portage/package.accept_keywords", 0600
        render_to_remote "/cloud_model/#{build_type}/etc/portage/package.use", "#{build_dir}/etc/portage/package.use", 0600

        # Copy dns configuration
        @host.exec! "cp -L /etc/resolv.conf #{build_dir}/etc/", 'Failed to copy resolv.conf'
      end
    
      def emerge_webrsync
        mkdir_p "#{build_dir}/usr/portage"
        chroot! build_dir, "emerge-webrsync", 'Failed to sync portage'
      end

      def emerge_sync
        chroot! build_dir, "emerge --sync --quiet", 'Failed to sync portage'
      end

      def emerge_portage
        chroot! build_dir, "emerge --oneshot portage", 'Failed to merge new portage'
      end

      def emerge_update_world
        chroot! build_dir, "emerge --update --newuse --deep --with-bdeps=y @world", 'Failed to update system packages'
      end

      def emerge_depclean
        chroot! build_dir, "emerge --depclean", 'Failed to clean up after updating system'
      end
    
      def perl_cleaner
        chroot! build_dir, "perl-cleaner --all", 'Failed to clean perl installation'
      end

      def python_cleaner
        chroot! build_dir, "python-updater -v", 'Failed to clean python installation'
      end
    
      def system_cleaner
        mkdir_p "#{build_dir}/var/cache/revdep-rebuild"
        chroot! build_dir, "revdep-rebuild", "Failed to clean system packages"
      end

      def emerge! packages
        chroot! build_dir, "emerge --autounmask=y #{packages * ' '}", 'Failed to merge needed packages'
      end
    
      def configure_udev
        chroot! build_dir, "ln -s /dev/null /etc/udev/rules.d/80-net-setup-link.rules", 'Failed to config network devices to old behaviour'
      end

      def configure_systemd
        chroot! build_dir, "ln -sf /proc/self/mounts /etc/mtab", "Failed to link mtab for systemd"

        mkdir_p "#{build_dir}/etc/systemd/system/sysinit.target.wants"
        mkdir_p "#{build_dir}/etc/systemd/system/network.target.wants"  
        mkdir_p "#{build_dir}/etc/systemd/system/basic.target.wants"  
        mkdir_p "#{build_dir}/etc/systemd/system/sockets.target.wants"  
        mkdir_p "#{build_dir}/etc/systemd/system/multi-user.target.wants"

        chroot! build_dir, "ln -s /usr/lib/systemd/system/dm-event.service /etc/systemd/system/sysinit.target.wants/", 'Failed to put dmevent service to autostart'
        chroot! build_dir, "ln -s /usr/lib/systemd/system/dm-event.socket /etc/systemd/system/sockets.target.wants/", 'Failed to put dmevent socket to autostart'
        chroot! build_dir, "ln -s /usr/lib/systemd/system/sshd.service /etc/systemd/system/multi-user.target.wants/", 'Failed to put SSH daemon to autostart'
        chroot! build_dir, "ln -s /usr/lib/systemd/system/tincd@.service /etc/systemd/system/multi-user.target.wants/tincd@vpn.service", 'Failed to put Tinc daemon to autostart'
        chroot! build_dir, "ln -s /usr/lib/systemd/system/libvirtd.service /etc/systemd/system/multi-user.target.wants/", 'Failed to put libvirt daemon to autostart'
      end
    
      def create_system_users
        # TODO: Make system user
        # TODO: config system users with ssh keys
        # TODO: use or create home
        # TODO; only allow root access on internal interface
        # TODO: only allow ssh key access
        raise 'skipped'
      end
    end
  end
end