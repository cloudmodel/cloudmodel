# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Mixins::UnattendedUpgrades do
  let(:host) { Factory :host, name: 'host01' }
  let(:guest) { Factory :guest, name: 'guest01', host: host, private_address: '10.42.0.11' }
  let(:install) { described_class::INSTALL }
  let(:check) { described_class::CHECK }
  let(:timers) { described_class::TIMERS }
  let(:tmpl) { described_class::TEMPLATE_DIR }

  describe 'the rendered templates' do
    subject(:worker) { CloudModel::Workers::HostWorker.new host }

    # The constant names the directory with its dots, BaseWorker#render maps
    # them to underscores — one real render pins the two to each other.
    it 'render through the dotted template path for both files and roles' do
      auto = worker.send(:render, "#{tmpl}/20auto-upgrades", role: :guest)
      expect(auto).to include 'APT::Periodic::Unattended-Upgrade "1";'
      %i(host guest).each do |role|
        out = worker.send(:render, "#{tmpl}/50unattended-upgrades", role: role)
        expect(out).to include 'Unattended-Upgrade::Origins-Pattern {'
        expect(out.include?('Package-Blacklist')).to eq(role == :host)
      end
    end
  end

  describe 'template build (install_unattended_upgrades)' do
    subject(:worker) { CloudModel::Workers::GuestTemplateWorker.new host }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:chroot!)
      allow(worker).to receive(:mkdir_p)
      allow(worker).to receive(:render_to_remote)
    end

    it 'writes both apt.conf.d files for the role, then installs and verifies' do
      expect(worker).to receive(:mkdir_p).with('/mnt/build/rootfs/etc/apt/apt.conf.d').ordered
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/20auto-upgrades", '/mnt/build/rootfs/etc/apt/apt.conf.d/20auto-upgrades', 0644, role: :host).ordered
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/50unattended-upgrades", '/mnt/build/rootfs/etc/apt/apt.conf.d/50unattended-upgrades', 0644, role: :host).ordered
      expect(worker).to receive(:chroot!).with('/mnt/build/rootfs', install, 'Failed to install unattended-upgrades').ordered
      expect(worker).to receive(:chroot!).with('/mnt/build/rootfs', check, /rejected the configuration/).ordered

      worker.install_unattended_upgrades '/mnt/build/rootfs', role: :host
    end

    it 'does nothing when switched off in the configuration' do
      allow(CloudModel.config).to receive(:unattended_upgrades).and_return(false)
      expect(worker).not_to receive(:chroot!)
      expect(worker).not_to receive(:render_to_remote)

      expect(worker.install_unattended_upgrades('/mnt/build/rootfs', role: :guest)).to eq false
    end
  end

  describe '(re)deploy from a template (refresh_unattended_upgrades)' do
    subject(:worker) { CloudModel::Workers::GuestWorker.new guest }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:chroot!)
      allow(worker).to receive(:mkdir_p)
      allow(worker).to receive(:render_to_remote)
    end

    it 'rewrites the configuration and installs the package only where it is missing' do
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/20auto-upgrades", '/var/lib/lxd/containers/guest01-x/rootfs/etc/apt/apt.conf.d/20auto-upgrades', 0644, role: :guest).ordered
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/50unattended-upgrades", '/var/lib/lxd/containers/guest01-x/rootfs/etc/apt/apt.conf.d/50unattended-upgrades', 0644, role: :guest).ordered
      expect(worker).to receive(:chroot!).with('/var/lib/lxd/containers/guest01-x/rootfs', "test -x /usr/bin/unattended-upgrade || { #{install}; }", 'Failed to install unattended-upgrades').ordered
      expect(worker).to receive(:chroot!).with('/var/lib/lxd/containers/guest01-x/rootfs', check, /rejected the configuration/).ordered

      worker.refresh_unattended_upgrades '/var/lib/lxd/containers/guest01-x/rootfs', role: :guest
    end

    it 'is a deploy step of the guest worker and of the host deploy' do
      expect(CloudModel::Workers::GuestWorker.instance_method(:deploy).source).to include "['Ensure unattended security upgrades', :ensure_unattended_upgrades]"
      expect(CloudModel::Workers::HostWorker.instance_methods).to include :refresh_unattended_upgrades
      expect(File.read(CloudModel::Workers::HostWorker.instance_method(:deploy).source_location.first)).to include 'refresh_unattended_upgrades root, role: :host'
    end
  end

  describe 'live push to a host (deploy_unattended_upgrades_to_host)' do
    subject(:worker) { CloudModel::Workers::HostWorker.new host }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:mkdir_p)
      allow(worker).to receive(:render_to_remote)
      allow(host).to receive(:exec!)
    end

    it 'writes both files in place, installs over ssh, verifies and enables the timers' do
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/20auto-upgrades", '/etc/apt/apt.conf.d/20auto-upgrades', 0644, role: :host).ordered
      expect(worker).to receive(:render_to_remote).with("#{tmpl}/50unattended-upgrades", '/etc/apt/apt.conf.d/50unattended-upgrades', 0644, role: :host).ordered
      expect(host).to receive(:exec!).with(install, 'Failed to install unattended-upgrades on host01').ordered
      expect(host).to receive(:exec!).with(check, /rejected the configuration on host01/).ordered
      expect(host).to receive(:exec!).with(timers, 'Failed to enable the apt timers').ordered

      worker.deploy_unattended_upgrades_to_host
    end
  end

  describe 'live push to a guest (deploy_unattended_upgrades_to_guest)' do
    subject(:worker) { CloudModel::Workers::GuestWorker.new guest }
    let(:container) { double CloudModel::LxdContainer, name: 'guest01-20260101000000', blank?: false }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:render_to_remote)
      allow(guest).to receive(:current_lxd_container).and_return(container)
      allow(guest).to receive(:exec!)
      allow(host).to receive(:exec!)
      allow(host).to receive(:exec)
      allow(SecureRandom).to receive(:hex).and_return('abcd')
    end

    it 'pushes both files as container root, installs inside the container through a shell, verifies and enables the timers' do
      %w(20auto-upgrades 50unattended-upgrades).each do |file|
        expect(worker).to receive(:render_to_remote).with("#{tmpl}/#{file}", "/tmp/cloud_model_apt_guest01-20260101000000_#{file}_abcd", 0644, role: :guest)
        expect(host).to receive(:exec!).with("lxc file push /tmp/cloud_model_apt_guest01-20260101000000_#{file}_abcd guest01-20260101000000/etc/apt/apt.conf.d/#{file} --uid 0 --gid 0 --mode 0644", "Failed to push #{file} to guest01-20260101000000")
        expect(host).to receive(:exec).with("rm -f /tmp/cloud_model_apt_guest01-20260101000000_#{file}_abcd")
      end
      expect(guest).to receive(:exec!).with("sh -c #{install.shellescape}", 'Failed to install unattended-upgrades in guest01-20260101000000').ordered
      expect(guest).to receive(:exec!).with("sh -c #{check.shellescape}", /rejected the configuration in guest01-20260101000000/).ordered
      expect(guest).to receive(:exec!).with(timers, 'Failed to enable the apt timers in guest01-20260101000000').ordered

      worker.deploy_unattended_upgrades_to_guest
    end

    it 'refuses without a running container' do
      allow(guest).to receive(:current_lxd_container).and_return(nil)
      expect { worker.deploy_unattended_upgrades_to_guest }.to raise_error(/no running LXD container/)
    end
  end

  it 'tolerates a failing apt-get update but not a failing install, and waits for the dpkg lock' do
    expect(install).to match(/apt-get update -q \|\| echo .*; DEBIAN_FRONTEND=noninteractive apt-get install -y -o DPkg::Lock::Timeout=600 unattended-upgrades\z/)
    expect(check).to start_with 'apt-config dump >/dev/null && /usr/bin/unattended-upgrade --dry-run'
  end
end
