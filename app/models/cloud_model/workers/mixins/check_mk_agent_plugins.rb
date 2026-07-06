module CloudModel
  module Workers
    module Mixins
      # Shared manifest and deployment of the check_mk agent plugin set.
      #
      # Used both when building a host image ({HostTemplateWorker}) and when
      # pushing the plugins to a live, already-running host over SSH/SFTP
      # ({HostWorker#deploy_check_mk_plugins}, driven by the
      # `cloudmodel:host:deploy_check_mk_plugins` rake task) — one source of
      # truth so the image build and the live push can never drift apart.
      module CheckMkAgentPlugins
        # Plugins that run on every agent poll.
        PLUGINS = %w(
          cgroup_cpu zfs lxd sensors smart systemd
          nf_conntrack net_dev ntp diskstats edac
        ).freeze

        # Heavier / low-churn plugins, deployed into a subdir named after a
        # number of seconds so the agent runs them asynchronously and caches
        # their output for that long instead of on every poll:
        # `{ cache_seconds => plugin_name }`.
        CACHED_PLUGINS = { '3600' => 'updates', '120' => 'kernel_log' }.freeze

        TEMPLATE_DIR = '/cloud_model/support/usr/lib/check_mk_agent/plugins'.freeze

        # Render every plugin template to `<base_path>/usr/lib/check_mk_agent/
        # plugins` with mode 0755. `base_path` is a build chroot when building an
        # image, or '' (the default) to target a live host's real filesystem via
        # the worker's SFTP session. The check_mk agent is socket-activated and
        # (re)reads its plugin dir on every connection, so a live push takes
        # effect on the next poll with no agent restart.
        def deploy_check_mk_plugins base_path = ''
          plugins_dir = "#{base_path}/usr/lib/check_mk_agent/plugins"

          mkdir_p plugins_dir
          PLUGINS.each do |plugin|
            render_to_remote "#{TEMPLATE_DIR}/#{plugin}", "#{plugins_dir}/#{plugin}", 0755
          end

          CACHED_PLUGINS.each do |cache_seconds, plugin|
            mkdir_p "#{plugins_dir}/#{cache_seconds}"
            render_to_remote "#{TEMPLATE_DIR}/#{plugin}", "#{plugins_dir}/#{cache_seconds}/#{plugin}", 0755
          end

          # On a live push (base_path == '') also refresh the cgroup CPU-usage
          # history writer that feeds the cgroup_cpu plugin — otherwise an
          # updated cgroup_cpu has no matching history to compute percentages
          # from. At build time the writer (and its systemd timer) are deployed
          # by install_check_mk_agent instead.
          if base_path.to_s.empty?
            render_to_remote '/cloud_model/support/usr/sbin/cgroup_load_writer', '/usr/sbin/cgroup_load_writer', 0755
          end
        end
      end
    end
  end
end
