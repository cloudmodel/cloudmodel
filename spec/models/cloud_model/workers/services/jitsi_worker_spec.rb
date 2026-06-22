# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::JitsiWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Jitsi.new}
  subject {CloudModel::Workers::Services::JitsiWorker.new lxc, model}

  describe 'write_config' do
    it 'should be a no-op' do
      expect(subject).not_to receive(:render_to_remote)
      expect(subject).not_to receive(:comment_sub_step)
      expect { subject.write_config }.not_to raise_error
    end
  end

  describe 'service_name' do
    it 'should return jitsi' do
      expect(subject.service_name).to eq 'jitsi'
    end
  end

  describe 'auto_restart' do
    it 'should return true' do
      expect(subject.auto_restart).to eq true
    end
  end

  describe 'auto_start' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(host).to receive(:exec)
      allow(host).to receive(:exec!)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
    end

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/jitsi.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should write the restart drop-in since auto_restart is true' do
      expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/systemd/system/jitsi.service.d')
      expect(subject).to receive(:render_to_remote).with("/cloud_model/support/etc/systemd/unit.d/restart.conf", "/var/lib/lxc/test/rootfs/etc/systemd/system/jitsi.service.d/restart.conf", 644)
      subject.auto_start
    end
  end
end
