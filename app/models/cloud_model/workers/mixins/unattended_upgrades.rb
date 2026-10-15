module CloudModel
  module Workers
    module Mixins
      # Unattended installation of security updates on hosts and guests.
      #
      # Baked into the host and guest core templates (so every system built
      # from them has it) and pushable to running systems
      # (`rake cloudmodel:host:deploy_unattended_upgrades`,
      # `rake cloudmodel:guest:deploy_unattended_upgrades`). Only the
      # distribution's security suite is applied, nothing reboots on its own,
      # and hosts never touch ZFS or the kernel this way — see the rendered
      # 50unattended-upgrades for the reasoning. Switched off with
      # `CloudModel.config.unattended_upgrades = false`.
      module UnattendedUpgrades
        # Rendered through BaseWorker#render, which maps dots to underscores
        # for the Rails view lookup — the files live in views/.../apt_conf_d.
        TEMPLATE_DIR = '/cloud_model/support/etc/apt/apt.conf.d'.freeze
        CONF_DIR = '/etc/apt/apt.conf.d'.freeze
        CONF_FILES = %w(20auto-upgrades 50unattended-upgrades).freeze
        PACKAGE = 'unattended-upgrades'.freeze
        # Package lists first: on a running system they are stale (404s on
        # superseded .deb versions otherwise); in a template build they are
        # fresh and the update is cheap.
        INSTALL = "apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y #{PACKAGE}".freeze

        # Template build: install the package and write the configuration
        # into the rootfs under construction.
        # @param base_path [String] rootfs being built
        # @param role [Symbol] :host or :guest
        def install_unattended_upgrades base_path, role:
          return skip_unattended_upgrades unless CloudModel.config.unattended_upgrades

          chroot! base_path, INSTALL, "Failed to install #{PACKAGE}"
          mkdir_p "#{base_path}#{CONF_DIR}"
          CONF_FILES.each do |file|
            render_to_remote "#{TEMPLATE_DIR}/#{file}", "#{base_path}#{CONF_DIR}/#{file}", 0644, role: role
          end
        end

        # Running host: install over SSH and write the configuration in place.
        def deploy_unattended_upgrades_to_host
          return skip_unattended_upgrades unless CloudModel.config.unattended_upgrades

          @host.exec! INSTALL, "Failed to install #{PACKAGE} on #{@host.name}"
          CONF_FILES.each do |file|
            render_to_remote "#{TEMPLATE_DIR}/#{file}", "#{CONF_DIR}/#{file}", 0644, role: :host
          end
          @host.exec! 'systemctl enable --now apt-daily.timer apt-daily-upgrade.timer', 'Failed to enable the apt timers'
        end

        # Running guest: install inside the container, push the configuration
        # with `lxc file push` (uid-mapping agnostic, container root).
        def deploy_unattended_upgrades_to_guest
          return skip_unattended_upgrades unless CloudModel.config.unattended_upgrades

          container = guest.current_lxd_container
          raise "Guest #{guest.name} has no running LXD container" if container.blank?
          cname = container.name

          # Guest commands go through `lxc exec` without a shell: wrap the chain.
          guest.exec! "sh -c #{INSTALL.shellescape}", "Failed to install #{PACKAGE} in #{cname}"
          CONF_FILES.each do |file|
            tmp = "/tmp/cloud_model_apt_#{cname}_#{file}_#{SecureRandom.hex(4)}"
            begin
              render_to_remote "#{TEMPLATE_DIR}/#{file}", tmp, 0644, role: :guest
              host.exec! "lxc file push #{tmp.shellescape} #{"#{cname}#{CONF_DIR}/#{file}".shellescape} --uid 0 --gid 0 --mode 0644",
                "Failed to push #{file} to #{cname}"
            ensure
              host.exec "rm -f #{tmp.shellescape}"
            end
          end
          guest.exec! 'systemctl enable --now apt-daily.timer apt-daily-upgrade.timer', "Failed to enable the apt timers in #{cname}"
        end

        private

        def skip_unattended_upgrades
          comment_sub_step 'Unattended upgrades disabled by configuration (config.unattended_upgrades)'
          false
        end
      end
    end
  end
end
