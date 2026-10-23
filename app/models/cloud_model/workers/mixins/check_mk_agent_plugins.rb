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
          nf_conntrack net_dev ntp diskstats edac versions kernel_log
        ).freeze

        # Heavier / low-churn plugins, deployed into a subdir named after a
        # number of seconds so the agent runs them asynchronously and caches
        # their output for that long instead of on every poll:
        # `{ cache_seconds => [plugin_names] }`. Agent 2.x prints such a
        # section only while the cache is younger than three times that, so
        # the interval must be at least a third of the poll interval — a
        # plugin polled hourly gets nothing from a 120 s cache. kernel_log
        # (1–2 s) therefore runs synchronously.
        CACHED_PLUGINS = { '3600' => %w(updates packages) }.freeze

        # Plugin files of earlier manifests, removed on deploy so they don't
        # run twice (`<subdir>/<plugin>` relative to the plugins dir).
        RETIRED_PLUGINS = %w(120/kernel_log).freeze

        TEMPLATE_DIR = '/cloud_model/support/usr/lib/check_mk_agent/plugins'.freeze
        AGENT_URL = 'https://raw.githubusercontent.com/Checkmk/checkmk/%s/agents/check_mk_agent.linux'.freeze

        # The agent script itself, same source as the image build, so a live
        # plugin push also brings an old host's agent to the current release
        # (1.2.8 agents left from earlier templates print stale plugin caches
        # and lack sections the parser knows from 2.x hosts). Fetched to a
        # temp file first: a failed download must not leave an empty agent.
        # @param base_path [String] build chroot, or '' for the live host
        def deploy_check_mk_agent base_path = ''
          url = AGENT_URL % CloudModel.config.check_mk_agent_version
          target = "#{base_path}/usr/bin/check_mk_agent"
          @host.exec! "curl -sSf -o #{target.shellescape}.new #{url.shellescape} && chmod 755 #{target.shellescape}.new && mv #{target.shellescape}.new #{target.shellescape}",
            'Failed to install the check_mk agent'
        end

        # Render every plugin template to `<base_path>/usr/lib/check_mk_agent/
        # plugins` with mode 0755. `base_path` is a build chroot when building an
        # image, or '' (the default) to target a live host's real filesystem via
        # the worker's SFTP session. The check_mk agent is socket-activated and
        # (re)reads its plugin dir on every connection, so a live push takes
        # effect on the next poll with no agent restart.
        def deploy_check_mk_plugins base_path = ''
          plugins_dir = "#{base_path}/usr/lib/check_mk_agent/plugins"

          deploy_check_mk_agent base_path
          mkdir_p plugins_dir
          PLUGINS.each do |plugin|
            render_to_remote "#{TEMPLATE_DIR}/#{plugin}", "#{plugins_dir}/#{plugin}", 0755
          end

          CACHED_PLUGINS.each do |cache_seconds, plugins|
            mkdir_p "#{plugins_dir}/#{cache_seconds}"
            plugins.each do |plugin|
              render_to_remote "#{TEMPLATE_DIR}/#{plugin}", "#{plugins_dir}/#{cache_seconds}/#{plugin}", 0755
            end
          end

          RETIRED_PLUGINS.each do |plugin|
            @host.exec "rm -f #{"#{plugins_dir}/#{plugin}".shellescape}; rmdir #{"#{plugins_dir}/#{File.dirname(plugin)}".shellescape} 2>/dev/null"
          end

          # The cgroup CPU-usage history writer feeds the cgroup_cpu plugin —
          # keep it in sync with the plugin set everywhere (image build, host
          # deploy from an older template, live push). Its systemd service/
          # timer units come from the image build and are not touched here.
          render_to_remote '/cloud_model/support/usr/sbin/cgroup_load_writer', "#{base_path}/usr/sbin/cgroup_load_writer", 0755
        end
      end
    end
  end
end
