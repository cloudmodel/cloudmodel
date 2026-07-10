module CloudModel
  module Workers
    # Worker that builds {CloudModel::GuestCoreTemplate} and {CloudModel::GuestTemplate} images.
    #
    # Builds happen inside a per-template ZFS dataset ({CloudModel::BuildZfsVolume}).
    # For core templates: bootstraps an Ubuntu/Debian root, installs utilities,
    # networking, SSH, and the check_mk monitoring agent, then commits the
    # dataset as a ready snapshot.
    #
    # For full guest templates: clones the core template's ready snapshot,
    # installs each component listed in the {CloudModel::GuestTemplateType},
    # writes the LXD metadata, and commits. Deploys then `zfs clone` the
    # committed snapshot — no tarballs are packed or synced.
    class GuestTemplateWorker < TemplateWorker
      include CloudModel::Workers::Mixins::CheckMkAgentGuestPlugins

      def zfs_volume
        @zfs_volume ||= @template.build_volume @host
      end

      # The template's rootfs inside the build dataset (LXD container layout)
      def build_path
        zfs_volume.rootfs_path
      end

      def error_log_object
        @template
      end

      def prepare_build_volume
        if resuming_build? and zfs_volume.dataset_exists? and not zfs_volume.ready?
          # Resuming an aborted build (skip_to) — keep what is there
          zfs_volume.mount!
        else
          zfs_volume.prepare!
        end
        mkdir_p build_path
        mkdir_p download_path
      end

      # True when the current build was started with skip_to, i.e. it resumes
      # an earlier, aborted build instead of starting fresh.
      def resuming_build?
        @build_options.present? and @build_options[:skip_to].present?
      end

      def commit_build_volume
        cleanup_chroot build_path
        zfs_volume.commit!
        zfs_volume.unmount!
      end

      def install_utils
        comment_sub_step 'Install gnupg'
        chroot! build_path, "apt-get install sudo gnupg -y", "Failed to install gnupg"

        comment_sub_step 'Install ppa support'
        chroot! build_path, "apt-get install apt-transport-https ca-certificates -y", "Failed to install ppa support"

        # Don't try to install software-properties-common on debian < 13, it is included in base template
        # chroot build_path, "apt-get install software-properties-common -y"

        comment_sub_step 'Install rsync, wget, and curl'
        chroot! build_path, "apt-get install sudo rsync wget curl -y", "Failed to install rsync, wget, and curl"

        comment_sub_step 'Install zstd'
        chroot! build_path, "apt-get install zstd -y", "Failed to install zstd"

        comment_sub_step 'Install nano editor'
        chroot! build_path, "apt-get install sudo nano -y", "Failed to install nano"

        comment_sub_step 'Install msmtp mailer'
        chroot! build_path, "apt-get install sudo msmtp msmtp-mta mailutils -y", "Failed to install msmtp"

        comment_sub_step 'Configure autologin'
        # Autologin
        mkdir_p "#{build_path}/etc/systemd/system/console-getty.service.d"
        render_to_remote "/cloud_model/guest/etc/systemd/system/console-getty.service.d/autologin.conf", "#{build_path}/etc/systemd/system/console-getty.service.d/autologin.conf"

        comment_sub_step 'Apply fixterm patch'
        # Tool for setting serial console size in terminal; call on virsh console to fix terminal size
        render_to_remote "/cloud_model/guest/bin/fixterm.sh", "#{build_path}/bin/fixterm", 0755
      end

      def install_network
        comment_sub_step 'Install netbase'
        chroot! build_path, "apt-get install netbase iproute2 isc-dhcp-client -y", "Failed to install network base"
        render_to_remote "/cloud_model/guest/etc/systemd/system/dhclient.service", "#{build_path}/etc/systemd/system/dhclient.service"
        mkdir_p "#{build_path}/etc/systemd/system/multi-user.target.wants"
        #chroot! build_path, "ln -s /etc/systemd/system/dhclient.service /etc/systemd/system/multi-user.target.wants/dhclient.service", "Failed to enable dhclient service"
      end

      def install_check_mk_agent
        #chroot! build_path, "apt-get install check-mk-agent -y", "Failed to install CheckMKAgent"

        chroot! build_path, "curl -s https://raw.githubusercontent.com/Checkmk/checkmk/2.2.0/agents/check_mk_agent.linux >/usr/bin/check_mk_agent && chmod 755 /usr/bin/check_mk_agent", "Failed to install CheckMKAgent"

        render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk@.service", "#{build_path}/etc/systemd/system/check_mk@.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/check_mk.socket", "#{build_path}/etc/systemd/system/check_mk.socket"
        mkdir_p "#{build_path}/etc/systemd/system/sockets.target.wants"
        chroot! build_path, "ln -s /etc/systemd/system/check_mk.socket /etc/systemd/system/sockets.target.wants/check_mk.socket", "Failed to add check_mk to autostart"

        render_check_mk_guest_plugins build_path

        # (cgroup_load_writer itself is rendered by render_check_mk_guest_plugins)
        render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.service", "#{build_path}/etc/systemd/system/cgroup_load_writer.service"
        render_to_remote "/cloud_model/guest/etc/systemd/system/cgroup_load_writer.timer", "#{build_path}/etc/systemd/system/cgroup_load_writer.timer"
        chroot! build_path, "ln -s /etc/systemd/system/cgroup_load_writer.timer /etc/systemd/system/timers.target.wants/cgroup_load_writer.timer", "Failed to enable cgroup_load_writer service"
      end

      # Strips data that must not be shared between containers cloned from
      # this template (the tarball flow excluded these from the tar):
      # SSH host keys + machine-id (see {BuildZfsVolume#scrub_identity!}),
      # caches, temp files, and docs.
      def cleanup_template
        comment_sub_step 'Clean apt caches'
        chroot! build_path, "apt-get clean", "Failed to clean apt caches"

        comment_sub_step 'Remove ssh host keys and machine id'
        zfs_volume.scrub_identity!
        render_to_remote "/cloud_model/guest/etc/systemd/system/regenerate_ssh_host_keys.service", "#{build_path}/etc/systemd/system/regenerate_ssh_host_keys.service"
        chroot! build_path, "ln -sf /etc/systemd/system/regenerate_ssh_host_keys.service /etc/systemd/system/multi-user.target.wants/regenerate_ssh_host_keys.service", "Failed to enable ssh host key regeneration"

        comment_sub_step 'Clear temporary files and docs'
        @host.exec! "rm -rf #{build_path}/tmp/* #{build_path}/var/tmp/* #{build_path}/run/* #{build_path}/var/cache/* #{build_path}/usr/share/man/* #{build_path}/usr/share/doc/*", "Failed to clear temporary files"
      end

      # Renders the LXD image metadata beside the rootfs. Cloned containers
      # carry it at their dataset root, as LXD expects.
      def write_lxd_metadata
        mkdir_p "#{@template.build_mountpoint}/templates"
        render_to_remote "/cloud_model/guest_template/metadata.yaml", "#{@template.build_mountpoint}/metadata.yaml", template: @template
        %w(hosts.tpl hostname.tpl).each do |file|
          render_to_remote "/cloud_model/guest_template/#{file}", "#{@template.build_mountpoint}/templates/#{file}", template: @template
        end
      end

      def build_core_template template, options={}
        unless template.build_state == :pending or options[:force]
          puts "Template not pending"
          return false
        end

        @template = template
        template.update_attributes build_state: :running, os_version: os_version

        steps = [
          ["Prepare build volume", :prepare_build_volume, no_skip: true],
          ["Download #{os_version}", :fetch_os],
          ["Update base system", :update_base],
          ["Install basic utils", :install_utils],
          ["Install network utils", :install_network],
          ["Install SSH server", :install_ssh],
          ["Install check_mk agent for monitoring", :install_check_mk_agent],
          ["Commit build volume", :commit_build_volume, no_skip: true]
        ]

        run_template_build steps, "Failed to build core image!", options
      end

      #---

      # Makes sure the template's core template exists and its volume is
      # ready on this host (synced from another host or built if missing).
      def ensure_core_template
        if @template.core_template.blank?
          @template.update_attributes core_template: CloudModel::GuestCoreTemplate.create!(arch: @host.arch, os_version: @template.os_version)
        end
        core_template = @template.core_template

        unless core_template.build_volume(@host).ready?
          comment_sub_step "Core template not available on host, syncing or building it"
          core_template.ensure_build_volume! @host
        end

        core_template
      end

      def clone_core_template
        core_template = ensure_core_template
        zfs_volume.prepare_from! core_template.build_dataset
        # Copy resolv.conf so the chroot can resolve during component install
        @host.exec! "cp /etc/resolv.conf #{build_path}/etc", "Failed to copy resolve conf"
      end

      def install_components
        chroot! build_path, "apt-get update", "Failed to update package lists"

        @template.template_type.components.each do |component_type|
          begin
            c = CloudModel::Components::BaseComponent.from_sym(component_type)
            comment_sub_step "Install #{c.human_name}"
            component = c.worker @template, @host
          rescue Exception => e
            CloudModel.log_exception e
            raise "Component :#{component_type} has no worker"
          end
          component.build build_path
        end
      end

      def build_template(template, options={})
        return false unless template.build_state == :pending or options[:force]

        @template = template
        template.update_attributes build_state: :running

        steps = [
          ["Clone core template #{template.core_template.try(:id)}", :clone_core_template, no_skip: true],
          ["Install Components", :install_components],
          ["Write LXD metadata", :write_lxd_metadata],
          # A skipped cleanup would silently commit a template with shared
          # identity; the step is idempotent. Uids stay unshifted — LXD
          # remaps each cloned container on first start
          # (see LxdContainer#attach_template_volume).
          ["Cleanup template for cloning", :cleanup_template, no_skip: true],
          ["Commit build volume", :commit_build_volume, no_skip: true]
        ]

        run_template_build steps, "Failed to build guest template!", options
      end

      private

      # Shared build runner: runs the steps, transitions build_state, marks
      # the volume failed and re-raises on error. @template must be set and
      # :running already recorded by the caller.
      def run_template_build steps, failure_message, options
        @build_options = options

        if options[:prepend_output]
          puts options[:prepend_output]
        end

        begin
          run_steps :build, steps, options
        rescue Exception => e
          CloudModel.log_exception e
          @template.update_attributes build_state: :failed, build_last_issue: "#{e}"
          cleanup_chroot build_path
          zfs_volume.fail!
          raise failure_message
        end

        @template.update_attributes build_state: :finished, build_last_issue: "", build_host: @host

        return @template
      end
    end
  end
end
