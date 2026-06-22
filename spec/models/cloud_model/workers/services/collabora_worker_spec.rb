# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::CollaboraWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Collabora.new}
  subject {CloudModel::Workers::Services::CollaboraWorker.new lxc, model}

  describe 'write_config' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(subject).to receive(:chroot!)
    end

    it 'should disable ssl via loolconfig' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', "loolconfig set ssl.enable false", "Failed to set collabora ssl option")
      subject.write_config
    end

    it 'should enable ssl termination via loolconfig' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', "loolconfig set ssl.termination true", "Failed to set collabora termination option")
      subject.write_config
    end

    it 'should not set wopi host when none is configured' do
      expect(subject).not_to receive(:chroot!).with(anything, /storage\.wopi\.host/, anything)
      subject.write_config
    end

    it 'should set the wopi host when configured' do
      model.wopi_host = 'nextcloud.example.com'
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', "loolconfig set storage.wopi.host nextcloud.example.com", "Failed to set collabora host option")
      subject.write_config
    end

    it 'should shellescape the wopi host' do
      model.wopi_host = 'foo; rm -rf /'
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', "loolconfig set storage.wopi.host #{'foo; rm -rf /'.shellescape}", "Failed to set collabora host option")
      subject.write_config
    end
  end

  describe 'service_name' do
    it 'should return loolwsd' do
      expect(subject.service_name).to eq 'loolwsd'
    end
  end

  describe 'auto_restart' do
    it 'should return true' do
      expect(subject.auto_restart).to eq true
    end
  end
end
