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
      end
      
      def remount_build_dir
        CloudModel::LogicalVolume.find_by(name: "build-#{build_type}").mount build_dir
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
        render_to_remote "/cloud_model/#{build_type}/etc/portage/make.conf", "#{build_dir}/etc/portage/make.conf", 0600, mirrors: CloudModel.config.gentoo_mirrors, host: @host, layman: false
        render_to_remote "/cloud_model/#{build_type}/etc/portage/package.accept_keywords", "#{build_dir}/etc/portage/package.accept_keywords", 0600
        render_to_remote "/cloud_model/#{build_type}/etc/portage/package.use", "#{build_dir}/etc/portage/package.use", 0600

        render_to_remote "/cloud_model/support/etc/vconsole.conf", "#{build_dir}/etc/vconsole.conf"
        
        # Configure locale
        render_to_remote "/cloud_model/support/etc/locale.gen", "#{build_dir}/etc/locale.gen"
        chroot! build_dir, "locale-gen", 'Failed to generate default locale'
        render_to_remote "/cloud_model/support/etc/locale.conf", "#{build_dir}/etc/locale.conf"

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
      
      def config_layman
        # Include CloudModel gentoo overlay
        mkdir_p "#{build_dir}/etc/layman"
        emerge! %w(
          app-portage/layman
        )
        render_to_remote "/cloud_model/support/etc/layman/layman.cfg", "#{build_dir}/etc/layman/layman.cfg"
        chroot! build_dir, "layman -S && layman -a CloudModel", 'Failed to add gentoo overlay'
        render_to_remote "/cloud_model/#{build_type}/etc/portage/make.conf", "#{build_dir}/etc/portage/make.conf", 0600, mirrors: CloudModel.config.gentoo_mirrors, host: @host, layman: true
      end

      def emerge! packages
        chroot! build_dir, "emerge --autounmask=y #{packages * ' '}", 'Failed to merge needed packages'
      end
      
      def emerge_postgres
        emerge! %w(
          dev-db/postgresql-server
        )
        
        version = "9.3" # TODO: Find actual version of postgres, not assuming one
        data_dir = "/var/lib/postgresql/#{version}/data"
        config_dir = "/etc/conf.d/postgresql-#{version}"

        # init database
        begin
          @host.ssh_connection.sftp.lstat! "#{build_dir}/#{data_dir}"
        rescue
          mkdir_p "#{build_dir}/#{data_dir}"
          chroot! build_dir, "chown -Rf postgres:postgres #{data_dir.shellescape}", "Can't assign data dir to postgres user"
          chroot! build_dir, "chmod 0700 #{data_dir.shellescape}", "Failed to change mod on data directory"

          chroot! build_dir, "su postgres -c '/usr/lib/postgresql-#{version}/bin/initdb -D #{data_dir.shellescape}'", "Failed to init database"
        end
        
        begin
          @host.ssh_connection.sftp.lstat! "#{build_dir}/#{config_dir}"          
        rescue
          mkdir_p "#{build_dir}/#{config_dir}"
          chroot! build_dir, "chown -Rf postgres:postgres #{data_dir.shellescape}", "Can't assign config dir to postgres user"
          chroot! build_dir, "mv #{data_dir}/*.conf #{config_dir}/", "Failed to copy config to #{config_dir}"      
        end
        
        true
      end
    
      def configure_udev
        chroot! build_dir, "ln -sf /dev/null /etc/udev/rules.d/80-net-setup-link.rules", 'Failed to config network devices to old behaviour'
      end

      def configure_systemd
        chroot! build_dir, "ln -sf /proc/self/mounts /etc/mtab", "Failed to link mtab for systemd"

        mkdir_p "#{build_dir}/etc/systemd/system/sysinit.target.wants"
        mkdir_p "#{build_dir}/etc/systemd/system/network.target.wants"  
        mkdir_p "#{build_dir}/etc/systemd/system/basic.target.wants"  
        mkdir_p "#{build_dir}/etc/systemd/system/sockets.target.wants"  
        mkdir_p "#{build_dir}/etc/systemd/system/multi-user.target.wants"
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