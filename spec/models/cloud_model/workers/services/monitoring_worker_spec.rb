# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::MonitoringWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Monitoring.new}
  subject {CloudModel::Workers::Services::MonitoringWorker.new lxc, model}

  describe 'write_config' do
    it 'should be a no-op' do
      expect { subject.write_config }.not_to raise_error
    end
  end

  describe 'service_name' do
    it 'should return monitoring' do
      expect(subject.service_name).to eq 'monitoring'
    end
  end

  describe 'auto_restart' do
    it 'should return false' do
      expect(subject.auto_restart).to eq false
    end
  end

  describe 'auto_start' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(host).to receive(:exec)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:chroot!)
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Write Monitoring systemd')
      subject.auto_start
    end

    it 'should render monitoring service unit' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/monitoring.service', '/var/lib/lxc/test/rootfs/etc/systemd/system/monitoring.service', guest: guest, model: model)
      subject.auto_start
    end

    it 'should link monitoring service to multi-user.target.wants' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', 'ln -s /etc/systemd/system/monitoring.service /etc/systemd/system/multi-user.target.wants/monitoring.service', 'Failed to enable monitoring service')
      subject.auto_start
    end
  end
end