# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::ForgejoRunnerWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host, name: 'ci'}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::ForgejoRunner.new instance_url: 'https://git.example.com/'}
  subject {CloudModel::Workers::Services::ForgejoRunnerWorker.new lxc, model}

  describe 'write_config' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:chroot!)
      allow(subject).to receive(:render_to_guest)
      allow(model).to receive(:save)
    end

    it 'should generate the 40 hex registration secret once' do
      expect(model).to receive(:save)
      subject.write_config
      expect(model.registration_secret).to match(/\A\h{40}\z/)

      secret = model.registration_secret
      subject.write_config
      expect(model.registration_secret).to eq secret
    end

    it 'should render the runner config and hand it to the runner user' do
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/forgejo_runner/config.yml', '/etc/forgejo-runner/config.yml', 0640, guest: guest, model: model)
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', 'chown root:forgejo-runner /etc/forgejo-runner/config.yml && chmod 640 /etc/forgejo-runner/config.yml', 'Failed to set runner config ownership')
      subject.write_config
    end

    it 'should refuse to deploy without an instance to connect to' do
      model.instance_url = nil
      expect { subject.write_config }.to raise_error(/needs an instance/)
    end

    context 'with a linked Forgejo service' do
      let(:forgejo) { double CloudModel::Services::Forgejo, name: 'Git' }
      before { allow(model).to receive(:forgejo_service).and_return forgejo }

      it 'should register the runner live on the instance' do
        expect(forgejo).to receive(:register_actions_runner!).with(model)
        subject.write_config
      end

      it 'should not fail the deploy when the live registration fails' do
        allow(forgejo).to receive(:register_actions_runner!).and_raise('instance down')
        expect(subject).to receive(:comment_sub_step).with(/Live registration failed \(instance down\)/)
        expect { subject.write_config }.not_to raise_error
      end
    end
  end

  describe 'auto_restart' do
    it { expect(subject.auto_restart).to eq true }
  end

  describe 'auto_start' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(host).to receive(:exec)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
    end

    it 'should render the fix_perms drop-in and enable the unit' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/forgejo_runner.service.d/fix_perms.conf', '/var/lib/lxc/test/rootfs/etc/systemd/system/forgejo_runner.service.d/fix_perms.conf')
      expect(host).to receive(:exec).with('ln -sf /lib/systemd/system/forgejo_runner.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/')
      subject.auto_start
    end
  end
end
