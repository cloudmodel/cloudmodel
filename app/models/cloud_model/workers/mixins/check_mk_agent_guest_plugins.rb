require 'securerandom'
require 'shellwords'

module CloudModel
  module Workers
    module Mixins
      # Shared manifest and deployment of the check_mk agent plugin set for
      # guests (LXD containers).
      #
      # Used both when building a guest image ({GuestTemplateWorker}, which
      # renders into a build chroot) and when pushing the plugins into a live,
      # running container over `lxc file push` ({GuestWorker#deploy_check_mk_plugins},
      # driven by the `cloudmodel:guest:deploy_check_mk_plugins` rake task) — one
      # source of truth so the image build and the live push can't drift apart.
      module CheckMkAgentGuestPlugins
        # Guest plugins run on every agent poll. Host-only sensors (conntrack,
        # net_dev, ntp, kernel_log, diskstats, updates, edac) are intentionally
        # absent — those are host-kernel concerns and GuestChecks never uses them.
        GUEST_PLUGINS = %w(cgroup_mem cgroup_cpu cgroup_limits df_k systemd guest_load).freeze

        # Cached (async) guest plugins: { cache_seconds => plugin_name }. None
        # yet; kept for symmetry with the host set so adding one is a one-liner.
        GUEST_CACHED_PLUGINS = {}.freeze

        TEMPLATE_DIR = '/cloud_model/support/usr/lib/check_mk_agent/plugins'.freeze

        PLUGINS_DIR = '/usr/lib/check_mk_agent/plugins'.freeze

        # Render the guest plugins into a rootfs under base_path — the build
        # chroot while building the guest image, or a container's mounted
        # rootfs during guest deploy (so deploying from an older template
        # doesn't silently downgrade monitoring). Also keeps the cgroup
        # CPU-usage history writer in sync (its systemd units come from the
        # image build).
        def render_check_mk_guest_plugins base_path
          plugins_dir = "#{base_path}#{PLUGINS_DIR}"

          mkdir_p plugins_dir
          GUEST_PLUGINS.each do |plugin|
            render_to_remote "#{TEMPLATE_DIR}/#{plugin}", "#{plugins_dir}/#{plugin}", 0755
          end
          GUEST_CACHED_PLUGINS.each do |cache_seconds, plugin|
            mkdir_p "#{plugins_dir}/#{cache_seconds}"
            render_to_remote "#{TEMPLATE_DIR}/#{plugin}", "#{plugins_dir}/#{cache_seconds}/#{plugin}", 0755
          end

          render_to_remote '/cloud_model/support/usr/sbin/cgroup_load_writer', "#{base_path}/usr/sbin/cgroup_load_writer", 0755
        end

        # Live: push the guest plugins into the running LXD container via
        # `lxc file push` (storage-backend- and uid-mapping-agnostic, mirroring
        # how the deploy worker writes files into containers). The agent is
        # socket-activated, so the new plugins take effect on the next poll with
        # no restart.
        def deploy_check_mk_plugins
          container = guest.current_lxd_container
          raise "Guest #{guest.name} has no running LXD container" if container.blank?
          cname = container.name

          guest.exec! "mkdir -p #{PLUGINS_DIR}", "Failed to create plugins dir in #{cname}"
          GUEST_PLUGINS.each do |plugin|
            push_file_to_guest cname, "#{TEMPLATE_DIR}/#{plugin}", "#{PLUGINS_DIR}/#{plugin}", plugin
          end
          GUEST_CACHED_PLUGINS.each do |cache_seconds, plugin|
            guest.exec! "mkdir -p #{PLUGINS_DIR}/#{cache_seconds}", "Failed to create cache dir in #{cname}"
            push_file_to_guest cname, "#{TEMPLATE_DIR}/#{plugin}", "#{PLUGINS_DIR}/#{cache_seconds}/#{plugin}", plugin
          end

          # Also refresh the cgroup CPU-usage history writer that feeds the
          # cgroup_cpu plugin (deployed as a plain sbin script, not a plugin).
          push_file_to_guest cname, '/cloud_model/support/usr/sbin/cgroup_load_writer', '/usr/sbin/cgroup_load_writer', 'cgroup_load_writer'
        end

        # Render a template to a temp file on the host, then push it into the
        # container as container-root (`--uid 0 --gid 0`) with mode 0755.
        # `label` only names the temp file; the random suffix keeps the path
        # unpredictable and collision-free across concurrent pushes.
        def push_file_to_guest cname, template, dest, label
          tmp = "/tmp/cloud_model_checkmk_#{cname}_#{label}_#{SecureRandom.hex(4)}"
          render_to_remote template, tmp, 0755
          host.exec! "lxc file push #{tmp.shellescape} #{"#{cname}#{dest}".shellescape} --uid 0 --gid 0 --mode 0755",
            "Failed to push #{label} to #{cname}"
        ensure
          host.exec "rm -f #{tmp.shellescape}" if tmp
        end
      end
    end
  end
end
