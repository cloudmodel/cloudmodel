require 'fileutils'
require 'net/http'
require 'net/sftp'
require 'securerandom'

module CloudModel
  class HostImageWorker < BaseWorker

    def host
      @host
    end
    
    def check_config
      unless CloudModel.config.gentoo_mirrors
        raise "You need to configure at least one gentoo_mirror in CloudModel.config.gentoo_mirrors"
      end
      true
    end

    def build_dir
      '/vm/build/host'
    end

    def prepare_build_dir
      unmount_build_dir

      #
      # Create and mount build root if necessary
      #
      unless @host.mounted_at? build_dir
        # puts "    Create build host partition"
        begin
          build_lv = CloudModel::LogicalVolume.find_by(name: 'build-host')
          build_lv.apply wipe: true
        rescue
          build_lv = CloudModel::LogicalVolume.create! name: 'build-host', disk_space: "32G", volume_group: @host.volume_groups.first
        end

        unless build_lv.mount build_dir
          raise 'Failed to mount build partition'
        end
      end

      # Mount boot device
      unless @host.mount_boot_fs build_dir
        raise "Failed to mount /boot to build system"
      end
    end

    def unmount_build_dir
      cleanup_chroot build_dir
      if @host.mounted_at? "#{build_dir}/boot"
        @host.exec! "umount #{build_dir}/boot", 'Failed to unmount boot device'
      end
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
      render_to_remote "/cloud_model/host/etc/portage/make.conf", "#{build_dir}/etc/portage/make.conf", 0600, mirrors: CloudModel.config.gentoo_mirrors, host: @host
      render_to_remote "/cloud_model/host/etc/portage/package.accept_keywords", "#{build_dir}/etc/portage/package.accept_keywords", 0600
      render_to_remote "/cloud_model/host/etc/portage/package.use", "#{build_dir}/etc/portage/package.use", 0600

      # Copy dns configuration
      @host.exec! "cp -L /etc/resolv.conf #{build_dir}/etc/", 'Failed to copy resolv.conf'
    end

    def configure_kernel
      # Configure gentoo parameters
      mkdir_p "#{build_dir}/etc/cloud_model"
      render_to_remote "/cloud_model/host/etc/cloud_model/kernel.config", "#{build_dir}/etc/cloud_model/kernel.config"
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

    def emerge! packages
      chroot! build_dir, "emerge --autounmask=y #{packages * ' '}", 'Failed to merge needed packages'
    end

    def emerge_kernel
      emerge! %w(
        sys-kernel/gentoo-sources
        sys-kernel/genkernel-next
        sys-kernel/linux-headers
      )
      chroot! build_dir, "eselect kernel set 1", 'Failed to select kernel sources'
    end

    def emerge_sys_tools
      emerge! %w(
        app-portage/mirrorselect
        app-portage/gentoolkit
        sys-boot/grub

        sys-apps/gptfdisk
        sys-apps/dbus
        sys-apps/kmod
        sys-apps/systemd
      )
    end

    def emerge_mon_tools
      emerge! %w(
        sys-apps/lm_sensors
        sys-apps/smartmontools
      )
    end

    def emerge_fs_tools
      emerge! %w(
        sys-fs/mdadm
        sys-fs/lvm2
      )
    end

    def emerge_net_tools
      emerge! %w(
        net-misc/networkmanager
        net-firewall/iptables
        sys-apps/iproute2
      )
    end

    def emerge_cm_packages
      emerge! %w(
        net-misc/openssh
        net-misc/tinc
        app-emulation/lxc
        app-emulation/libvirt
        mail-mta/nullmailer
      )
    end

    def compile_kernel
      render_to_remote "/cloud_model/host/etc/genkernel.conf", "#{build_dir}/etc/genkernel.conf", host: @host
      
      chroot! build_dir, "genkernel --kernel-config=/etc/cloud_model/kernel.config all", 'Failed to build kernel'
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

      # TODO: Config nullmailer to send mails
      chroot! build_dir, "ln -s /usr/lib/systemd/system/nullmailer.service /etc/systemd/system/multi-user.target.wants/", 'Failed to put nullmailer to autostart'

      # TODO: Make smartd run
      # - Add callback to CloudModel (?)
      render_to_remote "/cloud_model/host/etc/smartd.conf", "#{build_dir}/etc/smartd.conf", host: @host
      chroot! build_dir, "ln -s /usr/lib/systemd/system/smartd.service /etc/systemd/system/multi-user.target.wants/", 'Failed to put SMART daemon to autostart'
      # TODO: Make mdadm report errors
      # - Add email to notify
      # - Add callback to CloudModel (?)
      chroot! build_dir, "ln -s /usr/lib/systemd/system/mdadm.service /etc/systemd/system/multi-user.target.wants/", 'Failed to put MDADM to autostart'
      # TODO: Make lvm2 monitor report errors
      # - Add email to notify
      # - Add callback to CloudModel (?)
      chroot! build_dir, "ln -s /usr/lib/systemd/system/lvm2-monitor.service /etc/systemd/system/multi-user.target.wants/", 'Failed to put LVM2 monitor to autostart'

      # CloudModel firewall (for NAT etc.)
      render_to_remote "/cloud_model/host/etc/systemd/system/firewall.service", "#{build_dir}/etc/systemd/system/firewall.service", host: @host
      chroot build_dir, "ln -s /etc/systemd/system/firewall.service /etc/systemd/system/basic.target.wants/"

      # TODO: Enable lvmetad
      # - Patch /etc/lvm/lvm.conf
      #   - "use_lvmetad = 0" => "use_lvmetad = 1"
      #chroot! build_dir, "ln -s /usr/lib/systemd/system/lvm2-lvmetad.service /etc/systemd/system/sysinit.target.wants/", 'Failed to put LVM metalv daemon to autostart'
      #chroot! build_dir, "ln -s /usr/lib/systemd/system/lvm2-lvmetad.socket /etc/systemd/system/sockets.target.wants/", 'Failed to put LVM metalv socket to autostart'

      # TODO: Make monitoring run (nagios based; lm_sensors)
    end

    def configure_systemd_restart
      mkdir_p "#{build_dir}/etc/system/dm-event.service.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/dm-event.service.d/restart.conf"

      mkdir_p "#{build_dir}/etc/system/dm-event.socket.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/dm-event.socket.d/restart.conf"

      mkdir_p "#{build_dir}/etc/system/sshd.service.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/sshd.service.d/restart.conf"

      mkdir_p "#{build_dir}/etc/system/tincd@vpn.service.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/tincd@vpn.service.d/restart.conf"

      mkdir_p "#{build_dir}/etc/system/libvirtd.service.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/libvirtd.service.d/restart.conf"

      mkdir_p "#{build_dir}/etc/system/smartd.service.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/smartd.service.d/restart.conf"

      mkdir_p "#{build_dir}/etc/system/mdadm.service.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/mdadm.service.d/restart.conf"

      mkdir_p "#{build_dir}/etc/system/lvm2-monitor.service.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/lvm2-monitor.service.d/restart.conf"

      mkdir_p "#{build_dir}/etc/system/nullmailer.service.d"
      render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{build_dir}/etc/system/nullmailer.service.d/restart.conf"
    end

    def create_system_users
      # TODO: Make system user
      # TODO: config system users with ssh keys
      # TODO: use or create home
      # TODO; only allow root access on internal interface
      # TODO: only allow ssh key access
      raise 'skipped'
    end

    def package_boot
      @host.update_attributes build_state: :packaging
      build_tar './boot', "/inst/boot.tar.bz2", j:true, one_file_system: true, C: '/vm/build/host'
    end

    def package_root
      build_tar '.', "/inst/root.tar.bz2", j: true, one_file_system: true, exclude: [
        './etc/udev/rules.d/70-persistent-net.rules',
        './tmp/*',
        './var/tmp/*',
        './var/cache/*',
        './var/log/*',
        './inst/*',
        './vm/*',
        './etc/libvirt/lxc/*',
        './etc/tinc/vpn/*',
        './usr/share/man',
        './usr/share/doc',
        './usr/portage/*'
        ], C: '/vm/build/host'
    end
    
    def upload_images
      if CloudModel.config.skip_sync_images
        raise 'skipped'
      end

      @host.update_attributes build_state: :downloading
      `mkdir -p #{CloudModel.config.data_directory.shellescape}/inst`
      @host.ssh_connection.sftp.download! "/inst/boot.tar.bz2", "#{CloudModel.config.data_directory}/inst/boot.tar.bz2"
      @host.ssh_connection.sftp.download! "/inst/root.tar.bz2", "#{CloudModel.config.data_directory}/inst/root.tar.bz2"
    end
    
    def build_image options={}
      return false unless @host.build_state == :pending
       
      @host.update_attributes! build_state: :running, build_last_issue: nil
      
      build_start_at = Time.now
      
      steps = [
        ["Check config", :check_config],
        ["Prepare build dir", :prepare_build_dir],
        ["Get Gentoo stage3 image", [
          ["Download latest stage 3", :download_stage3],
          ["Unpack stage3 image", :unpack_stage3],
          ["Remove stage3 image", :remove_stage3],
        ]],
        ["Configure build parameters", :configure_build_system],
        ["Configure kernel config", :configure_kernel],
        ["Sync portage", [
          ["webrsync", :emerge_webrsync],
          ["sync", :emerge_sync],
        ]],
        ["Build system", [
          ["Update portage", :emerge_portage],
          ["Update base packages", :emerge_update_world],
          ["Cleanup base system", :emerge_depclean],
          ["Cleanup perl installation", :perl_cleaner],
          ["Fetch kernel", :emerge_kernel],
          ["Build system tools", :emerge_sys_tools],
          ["Build monitoring tools", :emerge_mon_tools],
          ["Build filesystem tools", :emerge_fs_tools],
          ["Build network tools", :emerge_net_tools],
          ["Build CloudModel packages", :emerge_cm_packages],
          ["Compile kernel", :compile_kernel],
        ]],
        ["Configure system", [
          ["Configure udev", :configure_udev],
          ["Configure systemd services and sockets", :configure_systemd],
          ["Adding Auto Restart flag to systemd services and sockets", :configure_systemd_restart],
          ["Add system users [TODO]", :create_system_users],
        ]],
        ["Create image files", [
          ["Create boot image", :package_boot],
          ["Create root image", :package_root],
          ["Copy image files to data directory for republication to other hosts", :upload_images],
        ]],
        ["Cleanup", :unmount_build_dir],
      ]
      
      run_steps :build, steps, options
    
      @host.update_attributes build_state: :finished
      
      puts "Finished building image in #{distance_of_time_in_words_to_now build_start_at}"
    end
    
  end
end