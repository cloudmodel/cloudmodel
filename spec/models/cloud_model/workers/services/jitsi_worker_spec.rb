# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::JitsiWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Jitsi.new}
  subject {CloudModel::Workers::Services::JitsiWorker.new lxc, model}

  describe 'write_config' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:chroot!)
    end

    context 'when the guest has no external hostname yet' do
      before { allow(guest).to receive(:external_hostname).and_return(nil) }

      it 'brands the UI and dedupes nginx, skipping the domain re-point' do
        expect(subject).to receive(:comment_sub_step).with('Brand jitsi UI')
        expect(subject).to receive(:chroot!).at_least(:once) # dedupe
        expect { subject.write_config }.not_to raise_error
      end
    end

    context 'when the guest has a real external hostname' do
      before { allow(guest).to receive(:external_hostname).and_return('meet.example.com') }

      it 're-points the stack from the build placeholder to the guest hostname' do
        expect(subject).to receive(:comment_sub_step).with(/Re-point jitsi/)
        # rename per-host files + rewrite references + regenerate certs (+ dedupe)
        expect(subject).to receive(:chroot!).at_least(3).times
        expect { subject.write_config }.not_to raise_error
      end
    end
  end

  describe 'set_interface_value' do
    before { allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs') }

    it 'escapes what sed and the JS string would otherwise interpret' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs',
        "sed -i \"s|^\\s*PROVIDER_NAME:.*|    PROVIDER_NAME: 'Meet \\& Greet \\| Co \\\\ Ltd\\\\'s',|\" /usr/share/jitsi-meet/interface_config.js",
        'Failed to set jitsi interface value PROVIDER_NAME')

      subject.send :set_interface_value, 'PROVIDER_NAME', "Meet & Greet | Co \\ Ltd's"
    end

    it 'keeps a multi-line value on one line' do
      expect(subject).to receive(:chroot!).with(anything, /PROVIDER_NAME: 'one two',/, anything)
      subject.send :set_interface_value, 'PROVIDER_NAME', "one\ntwo"
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
