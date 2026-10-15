# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Mixins::UnattendedUpgrades do
  let(:host) { Factory :host, name: 'host01' }
  let(:guest) { Factory :guest, name: 'guest01', host: host, private_address: '10.42.0.11' }

  describe 'template build (install_unattended_upgrades)' do
    subject(:worker) { CloudModel::Workers::GuestTemplateWorker.new host }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:chroot!)
      allow(worker).to receive(:mkdir_p)
      allow(worker).to receive(:render_to_remote)
    end

    it 'installs the package and writes both apt.conf.d files for the role' do
      expect(worker).to receive(:chroot!).with('/mnt/build/rootfs', 'apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades', 'Failed to install unattended-upgrades')
      expect(worker).to receive(:mkdir_p).with('/mnt/build/rootfs/etc/apt/apt.conf.d')
      expect(worker).to receive(:render_to_remote).with('/cloud_model/support/etc/apt/apt.conf.d/20auto-upgrades', '/mnt/build/rootfs/etc/apt/apt.conf.d/20auto-upgrades', 0644, role: :host)
      expect(worker).to receive(:render_to_remote).with('/cloud_model/support/etc/apt/apt.conf.d/50unattended-upgrades', '/mnt/build/rootfs/etc/apt/apt.conf.d/50unattended-upgrades', 0644, role: :host)

      worker.install_unattended_upgrades '/mnt/build/rootfs', role: :host
    end

    it 'does nothing when switched off in the configuration' do
      allow(CloudModel.config).to receive(:unattended_upgrades).and_return(false)
      expect(worker).not_to receive(:chroot!)
      expect(worker).not_to receive(:render_to_remote)

      expect(worker.install_unattended_upgrades('/mnt/build/rootfs', role: :guest)).to eq false
    end
  end

  describe 'live push to a host (deploy_unattended_upgrades_to_host)' do
    subject(:worker) { CloudModel::Workers::HostWorker.new host }

    before do
      allow(worker).to receive(:comment_sub_step)
      allow(worker).to receive(:render_to_remote)
      allow(host).to receive(:exec!)
    end

    it 'installs over ssh, writes the host configuration in place and enables the timers' do
      expect(host).to receive(:exec!).with('apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades', 'Failed to install unattended-upgrades on host01').ordered
      expect(worker).to receive(:render_to_remote).with('/cloud_model/support/etc/apt/apt.conf.d/50unattended-upgrades', '/etc/apt/apt.conf.d/50unattended-upgrades', 0644, role: :host)
      expect(host).to receive(:exec!).with('systemctl enable --now apt-daily.timer apt-daily-upgrade.timer', 'Failed to enable the apt timers').ordered

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

    it 'installs inside the container and pushes the guest configuration as container root' do
      expect(guest).to receive(:exec!).with("sh -c #{'apt-get update -q && DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades'.shellescape}", 'Failed to install unattended-upgrades in guest01-20260101000000').ordered
      expect(worker).to receive(:render_to_remote).with('/cloud_model/support/etc/apt/apt.conf.d/20auto-upgrades', '/tmp/cloud_model_apt_guest01-20260101000000_20auto-upgrades_abcd', 0644, role: :guest)
      expect(host).to receive(:exec!).with('lxc file push /tmp/cloud_model_apt_guest01-20260101000000_20auto-upgrades_abcd guest01-20260101000000/etc/apt/apt.conf.d/20auto-upgrades --uid 0 --gid 0 --mode 0644', 'Failed to push 20auto-upgrades to guest01-20260101000000')
      expect(host).to receive(:exec).with('rm -f /tmp/cloud_model_apt_guest01-20260101000000_20auto-upgrades_abcd')
      expect(guest).to receive(:exec!).with('systemctl enable --now apt-daily.timer apt-daily-upgrade.timer', 'Failed to enable the apt timers in guest01-20260101000000').ordered

      worker.deploy_unattended_upgrades_to_guest
    end

    it 'refuses without a running container' do
      allow(guest).to receive(:current_lxd_container).and_return(nil)
      expect { worker.deploy_unattended_upgrades_to_guest }.to raise_error(/no running LXD container/)
    end
  end
end
