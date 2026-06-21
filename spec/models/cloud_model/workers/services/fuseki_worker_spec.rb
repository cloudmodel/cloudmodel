# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::FusekiWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Fuseki.new}
  subject {CloudModel::Workers::Services::FusekiWorker.new lxc, model}

  describe 'write_config' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Write Fuseki config')
      subject.write_config
    end

    it 'should create fuseki config directory' do
      expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/fuseki')
      subject.write_config
    end

    it 'should render shiro.ini' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/fuseki/shiro.ini', '/var/lib/lxc/test/rootfs/etc/fuseki/shiro.ini', 0644, guest: guest, model: model)
      subject.write_config
    end

    it 'should render fuseki systemd service unit' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/fuseki.service', '/var/lib/lxc/test/rootfs/etc/systemd/system/fuseki.service', 0755, guest: guest, model: model)
      subject.write_config
    end
  end

  describe 'service_name' do
    it 'should return fuseki' do
      expect(subject.service_name).to eq 'fuseki'
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
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
    end

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/fuseki.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should not write restart drop-in since auto_restart is false' do
      expect(subject).not_to receive(:render_to_remote).with("/cloud_model/support/etc/systemd/unit.d/restart.conf", anything, anything)
      subject.auto_start
    end
  end
end