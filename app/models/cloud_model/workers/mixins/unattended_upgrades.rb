module CloudModel
  module Workers
    module Mixins
      # Unattended installation of security updates on hosts and guests.
      #
      # Installed into the host and guest core templates, re-applied on every
      # host and guest (re)deploy — a deploy clones the last finished
      # template, which may predate the feature — and pushable to running
      # systems (`rake cloudmodel:host:deploy_unattended_upgrades`,
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
        BINARY = '/usr/bin/unattended-upgrade'.freeze
        TIMERS = 'systemctl enable --now apt-daily.timer apt-daily-upgrade.timer'.freeze
        # Package lists first: on a running system they are stale (404s on
        # superseded .deb versions otherwise). A stale or broken third-party
        # list must not block the install, though — the package comes from
        # the distribution's own suite. The lock timeout rides out a running
        # apt-daily job instead of failing after apt's default two minutes.
        INSTALL = "apt-get update -q || echo 'apt-get update failed, installing from the existing package lists'; " \
                  "DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=600 #{PACKAGE}".freeze
        # A parse error in apt.conf.d breaks every apt call on the system,
        # deploys included — so what was written is verified before the step
        # reports success.
        CHECK = "apt-config dump >/dev/null && #{BINARY} --dry-run >/dev/null".freeze

        # Template build: write the configuration and install the package into
        # the rootfs under construction. (Configuration first: apt ignores
        # the keys until the package exists, and the package's own default —
        # full point releases, kernel included — is never active that way.)
        # @param base_path [String] rootfs being built
        # @param role [Symbol] :host or :guest
        def install_unattended_upgrades base_path, role:
          return skip_unattended_upgrades unless CloudModel.config.unattended_upgrades

          write_unattended_upgrades_config base_path, role: role
          chroot! base_path, INSTALL, "Failed to install #{PACKAGE}"
          chroot! base_path, CHECK, "#{PACKAGE} rejected the configuration in #{base_path}"
        end

        # (Re)deploy: the new root was cloned from a template that may predate
        # the feature, or carry an older configuration. Always rewrite the
        # configuration, install the package only where it is missing.
        # @param root [String] the system root being deployed
        # @param role [Symbol] :host or :guest
        def refresh_unattended_upgrades root, role:
          return skip_unattended_upgrades unless CloudModel.config.unattended_upgrades

          write_unattended_upgrades_config root, role: role
          chroot! root, "test -x #{BINARY} || { #{INSTALL}; }", "Failed to install #{PACKAGE}"
          chroot! root, CHECK, "#{PACKAGE} rejected the configuration in #{root}"
        end

        # Running host: write the configuration in place and install over SSH.
        def deploy_unattended_upgrades_to_host
          return skip_unattended_upgrades unless CloudModel.config.unattended_upgrades

          write_unattended_upgrades_config '', role: :host
          @host.exec! INSTALL, "Failed to install #{PACKAGE} on #{@host.name}"
          @host.exec! CHECK, "#{PACKAGE} rejected the configuration on #{@host.name}"
          @host.exec! TIMERS, 'Failed to enable the apt timers'
        end

        # Running guest: push the configuration with `lxc file push`
        # (uid-mapping agnostic, container root), install inside the
        # container. Guest commands go through `lxc exec` without a shell,
        # hence the `sh -c` wrapping.
        def deploy_unattended_upgrades_to_guest
          return skip_unattended_upgrades unless CloudModel.config.unattended_upgrades

          container = guest.current_lxd_container
          raise "Guest #{guest.name} has no running LXD container" if container.blank?
          cname = container.name

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
          guest.exec! "sh -c #{INSTALL.shellescape}", "Failed to install #{PACKAGE} in #{cname}"
          guest.exec! "sh -c #{CHECK.shellescape}", "#{PACKAGE} rejected the configuration in #{cname}"
          guest.exec! TIMERS, "Failed to enable the apt timers in #{cname}"
        end

        private

        # @param root [String] system root ('' for the host itself)
        def write_unattended_upgrades_config root, role:
          mkdir_p "#{root}#{CONF_DIR}"
          CONF_FILES.each do |file|
            render_to_remote "#{TEMPLATE_DIR}/#{file}", "#{root}#{CONF_DIR}/#{file}", 0644, role: role
          end
        end

        def skip_unattended_upgrades
          comment_sub_step 'Unattended upgrades disabled by configuration (config.unattended_upgrades)'
          false
        end
      end
    end
  end
end
