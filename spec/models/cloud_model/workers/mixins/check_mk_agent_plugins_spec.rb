# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Mixins::CheckMkAgentPlugins do
  # Exercise the mixin through a minimal worker including it.
  let(:worker) do
    klass = Class.new(CloudModel::Workers::BaseWorker) do
      include CloudModel::Workers::Mixins::CheckMkAgentPlugins
    end
    klass.new(double('host'))
  end

  before do
    allow(worker).to receive(:mkdir_p)
    allow(worker).to receive(:render_to_remote)
  end

  describe '#deploy_check_mk_plugins' do
    it 'renders every flat plugin to the live plugins dir with mode 0755' do
      worker.deploy_check_mk_plugins

      expect(worker).to have_received(:mkdir_p).with('/usr/lib/check_mk_agent/plugins')
      described_class::PLUGINS.each do |plugin|
        expect(worker).to have_received(:render_to_remote).with(
          "/cloud_model/support/usr/lib/check_mk_agent/plugins/#{plugin}",
          "/usr/lib/check_mk_agent/plugins/#{plugin}",
          0755
        )
      end
    end

    it 'renders cached plugins into their numbered cache subdir' do
      worker.deploy_check_mk_plugins

      described_class::CACHED_PLUGINS.each do |cache_seconds, plugins|
        expect(worker).to have_received(:mkdir_p).with("/usr/lib/check_mk_agent/plugins/#{cache_seconds}")
        plugins.each do |plugin|
          expect(worker).to have_received(:render_to_remote).with(
            "/cloud_model/support/usr/lib/check_mk_agent/plugins/#{plugin}",
            "/usr/lib/check_mk_agent/plugins/#{cache_seconds}/#{plugin}",
            0755
          )
        end
      end
    end

    it 'includes the versions and packages plugins' do
      expect(described_class::PLUGINS).to include('versions')
      expect(described_class::CACHED_PLUGINS.values.flatten).to include('packages')
    end

    it 'prefixes a build chroot path when given one' do
      worker.deploy_check_mk_plugins '/cloud/build/host/1'

      expect(worker).to have_received(:render_to_remote).with(
        anything, '/cloud/build/host/1/usr/lib/check_mk_agent/plugins/nf_conntrack', 0755
      )
    end

    it 'keeps the cgroup_load_writer in sync on a live push' do
      worker.deploy_check_mk_plugins ''
      expect(worker).to have_received(:render_to_remote).with(
        '/cloud_model/support/usr/sbin/cgroup_load_writer', '/usr/sbin/cgroup_load_writer', 0755
      )
    end

    it 'keeps the cgroup_load_writer in sync in a build/deploy root' do
      worker.deploy_check_mk_plugins '/cloud/build/host/1'
      expect(worker).to have_received(:render_to_remote).with(
        '/cloud_model/support/usr/sbin/cgroup_load_writer', '/cloud/build/host/1/usr/sbin/cgroup_load_writer', 0755
      )
    end
  end
end
