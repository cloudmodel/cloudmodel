module CloudModel
  module Workers
    # Worker that deploys and redeploys a {CloudModel::Guest} (LXD container).
    #
    # Orchestrates the full guest deployment lifecycle:
    # ZFS template volume → container creation (cloned from the template
    # snapshot) → custom volume setup → service configuration →
    # network/firewall → container start.
    # Each phase is a named step that can be skipped via the `skip_to` option.
    class GuestWorker < BaseWorker
      include CloudModel::Workers::Mixins::UnattendedUpgrades
      include CloudModel::Workers::Mixins::CheckMkAgentGuestPlugins

      def initialize(guest)
        @guest = guest
        @host = @guest.host
      end

      def host
        @host
      end

      def guest
        @guest
      end

      def error_log_object
        guest
      end

      # Files and directories are written as root into the unshifted
      # template-volume clone; LXD maps uid 0 to the container's root on
      # first start, so no host-range chown is needed (or correct) here.

      # Makes sure the guest's template is available as a ZFS volume on the
      # guest's host, so the container can be cloned from its ready snapshot.
      # Missing volumes are synced over from the build host (zfs send/receive)
      # or built if no host has them; concurrent deploys are serialized by an
      # atomic build claim (see Mixins::HasZfsBuildVolume).
      def ensure_zfs_template
        @template = guest.template
        unless @template.build_volume(host).ready?
          comment_sub_step "Template not available as ZFS volume on host, syncing or building it"
          @template.ensure_build_volume! host
        end
      end

      def create_lxd_container
        # @template was resolved by ensure_zfs_template (a no_skip step)
        @lxc = guest.lxd_containers.new guest_template: @template, created_at: Time.now, updated_at: Time.now
        @lxc.save!
        @lxc.mount
        host.exec!("echo #{"Deployed at #{Time.now} with CloudModel".shellescape} | lxc file push - #{@lxc.name}/etc/deployed", "Failed to render deploy stemp")
      end

      def mount_lxd_container
        @lxc = guest.lxd_containers.desc(:created_at).first
        comment_sub_step "Mounting guests/containers/#{@lxc.name} to #{@lxc.mountpoint}"
        @lxc.mount
        host.exec!("echo #{"Resumed deployment at #{Time.now} with CloudModel".shellescape} | lxc file push - #{@lxc.name}/etc/deployed.resume", "Failed to render deploy stemp")
      end

      def ensure_lxd_custom_volumes
        guest.lxd_custom_volumes.each do |volume|
          if volume.volume_exists?
            # ZFS properties (primarycache) may have been changed since the
            # volume was created — a redeploy is where they get applied.
            volume.apply_zfs_properties!
          else
            volume.create_volume!
            seed_custom_volume volume
          end
        end
      end

      # A volume added to a guest that already runs starts out with what the
      # running container keeps at its mount point (LxdCustomVolume
      # #seed_from_rootfs) — copied while the old container still serves, so
      # the switch-over finds the data in place.
      def seed_custom_volume volume
        return unless volume.seed_from_rootfs
        previous = guest.current_lxd_container
        previous ||= guest.lxd_containers.desc(:created_at).to_a.find { |c| c != @lxc }
        return unless previous

        comment_sub_step "Seed volume #{volume.name} from #{previous.name}:/#{volume.mount_point}"
        unless volume.seed_from_container! previous
          comment_sub_step "Nothing to seed: #{previous.name} has no /#{volume.mount_point}"
        end
      end

      def config_lxd_container
        @lxc.config_from_guest
      end

      def start_lxd_container
        cleanup_chroot guest.deploy_path
        @lxc.unmount
        #host.exec! "rm -f #{@lxc.mountpoint}/*", "Failed to clear mountpoint for container"
        guest.update_attributes deploy_state: :booting
        guest.stop
        guest.start @lxc
      end

      def config_services
        #@lxc.mount
        guest.deploy_path = "#{@lxc.mountpoint}/rootfs"

        guest.services.each do |service|
          comment_sub_step "#{service.class.model_name.element.camelcase} '#{service.name}'"
          increase_indent
          begin
            service_worker_class = "CloudModel::Workers::Services::#{service.class.model_name.element.camelcase}Worker".constantize
            service_worker = service_worker_class.new @lxc, service
            service_worker.set_indent current_indent

            service_worker.write_config
            service_worker.auto_start
          rescue Exception => e
            CloudModel.log_exception e

            puts e
            puts e.backtrace

            raise "Failed to configure service #{service.class.model_name.element.camelcase} '#{service.name}'"
          end
          decrease_indent
        end
        mkdir_p "#{guest.deploy_path}/usr/share/cloud_model/"
        render_to_remote "/cloud_model/guest/usr/share/cloud_model/fix_permissions.sh", "#{guest.deploy_path}/usr/share/cloud_model/fix_permissions.sh", 0755, guest: guest
        host.exec! "rm -f #{guest.deploy_path}/usr/sbin/policy-rc.d", "Failed to remove policy-rc.d"
      end

      # Refresh the monitoring plugin set in the container's rootfs: the guest
      # template may be older than the current plugin set, and a (re)deploy
      # must not silently downgrade monitoring.
      def update_check_mk_plugins
        render_check_mk_guest_plugins guest.deploy_path
      end

      # Same reason as the plugins: the template behind the clone may predate
      # unattended security upgrades, or carry an older configuration.
      def ensure_unattended_upgrades
        refresh_unattended_upgrades guest.deploy_path, role: :guest
      end

      def config_guest_certificates
        guest.guest_certificates.each do |cert|
          unless cert.path_to_crt.blank?
            crt_file, in_release = offline_file_path cert.path_to_crt
            mkdir_p File.dirname(crt_file)
            @host.sftp.file.open(crt_file, 'w') do |f|
              f.write cert.certificate.crt
            end
            own_as_www crt_file if in_release
          end

          unless cert.path_to_key.blank?
            key_file, in_release = offline_file_path cert.path_to_key
            mkdir_p File.dirname(key_file)
            @host.sftp.file.open(key_file, 'w') do |f|
              f.write cert.certificate.key
            end
            own_as_www key_file if in_release
            host.exec! "chmod 0700 #{key_file}", "failed to limit rights for #{key_file}"
          end
        end
      end

      # Where a container path is written during an offline deploy: normally
      # below the rootfs. A path inside a web release (`<www_root>/current/…`)
      # is the exception — `current` is a symlink to `releases/<id>`, a disk
      # device LXD only mounts when the container starts, so on the host the
      # link dangles and writing through it fails. Such a path goes to the
      # release clone's host mountpoint, which is what that device serves.
      # @return [Array(String, Boolean)] host path and whether it is in a release
      def offline_file_path container_path
        guest.services.each do |service|
          next unless service.respond_to?(:www_root) and service.try(:deploy_web_image)

          current = "#{service.www_root}/current"
          next unless container_path.start_with? "#{current}/"

          success, link = @host.exec "readlink #{"#{guest.deploy_path}#{current}".shellescape}"
          deploy_id = link.to_s.strip[%r{/releases/(\d+)\z}, 1] if success
          next unless deploy_id

          mount = CloudModel::Workers::Services::NginxWorker.web_clone_mount guest, deploy_id
          return ["#{mount}#{container_path.delete_prefix current}", true]
        end

        ["#{guest.deploy_path}#{container_path}", false]
      end

      # Files in a release clone are read by the app as www; the clone is not
      # id-shifted by LXD, so own them by the container's mapped uid (see
      # Services::NginxWorker#own_web_release_config).
      def own_as_www file
        uid = @lxc.host_uid CloudModel::Workers::Services::NginxWorker::WWW_UID
        @host.exec! "chown #{uid}:#{uid} #{file.shellescape}", "Failed to own #{file}"
      end

      def config_network
        if true
          mkdir_p "#{guest.deploy_path}/etc/systemd/system"
          render_to_remote "/cloud_model/guest/etc/systemd/system/network.service", "#{guest.deploy_path}/etc/systemd/system/network.service", guest: @guest, host: @host
          chroot guest.deploy_path, "ln -sf /etc/systemd/system/network.service /etc/systemd/system/multi-user.target.wants/"
          render_to_remote "/cloud_model/support/etc/systemd/resolved.conf", "#{guest.deploy_path}/etc/systemd/resolved.conf", host: @host
        else
          mkdir_p "#{guest.deploy_path}/etc/systemd/network"
          render_to_remote "/cloud_model/support/etc/systemd/network/eth0.network", "#{guest.deploy_path}/etc/systemd/network/eth0.network", 0644, address: guest.private_address, subnet: host.private_network.subnet, gateway: host.private_address

          chroot guest.deploy_path, "ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/dbus-org.freedesktop.network1.service"
          chroot guest.deploy_path, "ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service"
          chroot guest.deploy_path, "ln -sf /lib/systemd/system/systemd-networkd.socket /etc/systemd/system/sockets.target.wants/systemd-networkd.socket"
          mkdir_p "#{guest.deploy_path}/etc/systemd/system/network-online.target.wants"
          chroot guest.deploy_path, "ln -sf /lib/systemd/system/systemd-networkd-wait-online.service /etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service"
        end
        # config mail out
        render_to_remote "/cloud_model/guest/etc/msmtprc", "#{guest.deploy_path}/etc/msmtprc", guest: guest

        # LXD applied /etc/hostname and /etc/hosts through image templates on
        # container create; containers cloned from ZFS volumes get them here.
        render_to_remote "/cloud_model/guest/etc/hostname", "#{guest.deploy_path}/etc/hostname", container_name: @lxc.name
        render_to_remote "/cloud_model/guest/etc/hosts", "#{guest.deploy_path}/etc/hosts", container_name: @lxc.name
      end

      def config_firewall
        # The host firewall covers every guest of the host; a batch redeploy
        # (Guest.redeploy_batch!) restarts it once at the end instead.
        if (@deploy_options || {})[:skip_firewall]
          comment_sub_step "Firewall restart deferred to the end of the batch"
          return
        end
        comment_sub_step "Restart Firewall"
        host.restart_firewall
      end

      def activate_address_resolution
        if resolution = guest.external_address_resolution
          resolution.update_attributes! name: guest.external_hostname, active: true
        end
      end

      # Builds the guest's new container and, unless `launch: false`, switches
      # the guest over to it. With `launch: false` everything up to the switch
      # is done — the new container sits ready beside the running old one,
      # the guest is marked :prepared — and {#launch_prepared!} does the
      # switch later (e.g. in a batch, off-hours). `skip_firewall` leaves the
      # host firewall restart to the caller (a batch does it once per host).
      def deploy options={}
        return false unless guest.deploy_state == :pending or options[:force]
        @deploy_options = options

        guest.update_attributes deploy_state: :running, deploy_last_issue: nil

        build_start_at = Time.now

        steps = [
          ['Ensure ZFS template volume', :ensure_zfs_template, no_skip: true],
          ['Create LXD container', :create_lxd_container, on_skip: :mount_lxd_container],
          ['Ensure LXD custom volumes', :ensure_lxd_custom_volumes, no_skip: true],
          ['Config LXD container', :config_lxd_container],
          ['Config guest services', :config_services],
          ['Update check_mk agent plugins', :update_check_mk_plugins],
          ['Ensure unattended security upgrades', :ensure_unattended_upgrades],
          ['Config guest certificates', :config_guest_certificates],
          ['Config network', :config_network],
          ['Config firewall', :config_firewall],
          ['Activate Address Resolution', :activate_address_resolution],
        ]
        if options[:launch] == false
          steps << ['Leave container prepared (switch-over deferred)', :leave_prepared]
        else
          steps << ['Launch LXD container', :start_lxd_container]
        end

        begin
          run_steps :deploy, steps, options
        rescue Exception => e
          cleanup_chroot_quietly guest.deploy_path
          @lxc.unmount unless @lxc.blank?
          raise e
        end

        if options[:launch] == false
          guest.collection.update_one({_id: guest.id}, '$set' => { 'deploy_state_id': 0xe1, 'deploy_prepared_at': Time.now })
          puts "Prepared container #{@lxc.name} in #{distance_of_time_in_words_to_now build_start_at}; the guest keeps running on #{guest.current_lxd_container.try(:name) || 'its current container'} until the switch-over"
          Rails.logger.debug "GUEST_WORKER: Prepared guest #{guest.name} container #{@lxc.name} in #{Time.now - build_start_at}"
          return
        end

        mark_deployed
        puts "Finished deploy host in #{distance_of_time_in_words_to_now build_start_at}"
        Rails.logger.debug "GUEST_WORKER: Deploy guest #{guest.name} on container #{@lxc.name} done in #{Time.now - build_start_at}"
      end

      def redeploy options={}
        deploy options
      end

      # The deferred half of a `launch: false` deploy: switches the guest over
      # to the container prepared last (the newest), i.e. stops the running
      # one and starts the new one. Everything else was done at preparation.
      # @raise [RuntimeError] unless the guest is :prepared
      def launch_prepared! options={}
        unless guest.deploy_state == :prepared or options[:force]
          raise "Guest #{guest.name} has no prepared container (deploy_state #{guest.deploy_state})"
        end
        @deploy_options = options
        @lxc = guest.lxd_containers.desc(:created_at).first
        raise "Guest #{guest.name} has no container to switch to" if @lxc.blank?
        guest.deploy_path = "#{@lxc.mountpoint}/rootfs"

        start_at = Time.now
        guest.update_attributes deploy_state: :running, deploy_last_issue: nil
        begin
          run_steps :launch, [['Launch LXD container', :start_lxd_container]], options
        rescue Exception => e
          guest.update_attributes deploy_state: :failed, deploy_last_issue: "#{e}"
          raise e
        end

        mark_deployed
        puts "Switched #{guest.name} to #{@lxc.name} in #{distance_of_time_in_words_to_now start_at}"
      end

      private

      # Last preparation step in place of the launch: drop the chroot
      # submounts and unmount the new container's rootfs, as the launch would
      # have done before starting it.
      def leave_prepared
        cleanup_chroot guest.deploy_path
        @lxc.unmount
      end

      def mark_deployed
        guest.collection.update_one({_id: guest.id}, '$set' => { 'deploy_state_id': 0xf0, 'last_deploy_finished_at': Time.now, 'deploy_prepared_at': nil })

        # The fresh deploy reflects the stored config — clear staged markers.
        guest.services.each do |service|
          service.set config_staged_at: nil, config_staged_deploy_required: false, config_staged_changes: [] if service.config_staged?
        end
      end
    end
  end
end