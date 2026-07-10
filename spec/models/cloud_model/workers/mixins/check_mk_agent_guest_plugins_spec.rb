# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Mixins::CheckMkAgentGuestPlugins do
  let(:container) { double('lxd_container', name: 'guest-1') }
  let(:host) { double('host') }
  let(:guest) { double('guest', name: 'guest-1', current_lxd_container: container) }

  # Exercise the mixin through a minimal worker exposing host/guest.
  let(:worker) do
    klass = Class.new(CloudModel::Workers::BaseWorker) do
      include CloudModel::Workers::Mixins::CheckMkAgentGuestPlugins
      attr_accessor :guest
      def initialize(host, guest); @host = host; @guest = guest; end
      def host; @host; end
    end
    klass.new(host, guest)
  end

  before do
    allow(worker).to receive(:render_to_remote)
    allow(guest).to receive(:exec!)
    allow(host).to receive(:exec!)
    allow(host).to receive(:exec)
  end

  describe '#render_check_mk_guest_plugins (build)' do
    it 'renders each guest plugin into the chroot plugins dir' do
      allow(worker).to receive(:mkdir_p)

      worker.render_check_mk_guest_plugins '/cloud/build/guest/1'

      expect(worker).to have_received(:mkdir_p).with('/cloud/build/guest/1/usr/lib/check_mk_agent/plugins')
      described_class::GUEST_PLUGINS.each do |plugin|
        expect(worker).to have_received(:render_to_remote).with(
          "/cloud_model/support/usr/lib/check_mk_agent/plugins/#{plugin}",
          "/cloud/build/guest/1/usr/lib/check_mk_agent/plugins/#{plugin}",
          0755
        )
      end
    end

    it 'keeps the cgroup_load_writer in sync with the plugin set' do
      allow(worker).to receive(:mkdir_p)

      worker.render_check_mk_guest_plugins '/cloud/build/guest/1'

      expect(worker).to have_received(:render_to_remote).with(
        '/cloud_model/support/usr/sbin/cgroup_load_writer', '/cloud/build/guest/1/usr/sbin/cgroup_load_writer', 0755
      )
    end

    it 'renders cached guest plugins (packages) into their cache subdir' do
      allow(worker).to receive(:mkdir_p)

      worker.render_check_mk_guest_plugins '/cloud/build/guest/1'

      described_class::GUEST_CACHED_PLUGINS.each do |cache_seconds, plugins|
        expect(worker).to have_received(:mkdir_p).with("/cloud/build/guest/1/usr/lib/check_mk_agent/plugins/#{cache_seconds}")
        plugins.each do |plugin|
          expect(worker).to have_received(:render_to_remote).with(
            "/cloud_model/support/usr/lib/check_mk_agent/plugins/#{plugin}",
            "/cloud/build/guest/1/usr/lib/check_mk_agent/plugins/#{cache_seconds}/#{plugin}",
            0755
          )
        end
      end
    end

    it 'includes versions in guest plugins and packages in cached guest plugins' do
      expect(described_class::GUEST_PLUGINS).to include('versions')
      expect(described_class::GUEST_CACHED_PLUGINS.values.flatten).to include('packages')
    end
  end

  describe '#deploy_check_mk_plugins (live)' do
    it 'creates the plugins dir and lxc-file-pushes each plugin as container root' do
      worker.deploy_check_mk_plugins

      expect(guest).to have_received(:exec!).with('mkdir -p /usr/lib/check_mk_agent/plugins', anything)
      described_class::GUEST_PLUGINS.each do |plugin|
        expect(host).to have_received(:exec!).with(
          %r{lxc file push /tmp/cloud_model_checkmk_guest-1_#{plugin}_\h{8} guest-1/usr/lib/check_mk_agent/plugins/#{plugin} --uid 0 --gid 0 --mode 0755},
          anything
        )
      end
    end

    it 'raises when the guest has no running container' do
      allow(guest).to receive(:current_lxd_container).and_return nil
      expect { worker.deploy_check_mk_plugins }.to raise_error(/no running LXD container/)
    end

    it 'cleans up the temp file even after a push' do
      worker.deploy_check_mk_plugins
      expect(host).to have_received(:exec).with(%r{rm -f /tmp/cloud_model_checkmk_guest-1_}).at_least(:once)
    end

    it 'also refreshes the cgroup_load_writer sbin in the container' do
      worker.deploy_check_mk_plugins
      expect(worker).to have_received(:render_to_remote).with('/cloud_model/support/usr/sbin/cgroup_load_writer', anything, 0755)
      expect(host).to have_received(:exec!).with(
        %r{lxc file push \S+ guest-1/usr/sbin/cgroup_load_writer --uid 0 --gid 0 --mode 0755}, anything
      )
    end
  end
end
