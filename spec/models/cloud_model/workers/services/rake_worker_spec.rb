require 'spec_helper'

describe CloudModel::Workers::Services::RakeWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Rake.new}
  subject {CloudModel::Workers::Services::RakeWorker.new lxc, model}

  describe 'write_config' do
    it 'should be a no-op' do
      expect { subject.write_config }.not_to raise_error
    end
  end

  describe 'service_name' do
    it 'should return sshd' do
      expect(subject.service_name).to eq 'rake'
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
      model.rake_task = 'test:task'
    end

    it 'should render rake service unit' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/rake.service', '/var/lib/lxc/test/rootfs/etc/systemd/system/rake-test:task.service', 644, service: model)
      subject.auto_start
    end

    context 'with timer mode (default)' do
      before do
        model.rake_mode = 'timer'
      end

      it 'should comment adding rake timer' do
        expect(subject).to receive(:comment_sub_step).with('Add Rake timer to runlevel default')
        subject.auto_start
      end

      it 'should create timers.target.wants directory' do
        expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/systemd/system/timers.target.wants')
        subject.auto_start
      end

      it 'should render rake timer unit' do
        expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/rake.timer', '/var/lib/lxc/test/rootfs/etc/systemd/system/rake-test:task.timer', 644, service: model)
        subject.auto_start
      end

      it 'should link timer to timers.target.wants' do
        expect(host).to receive(:exec).with("ln -sf /etc/systemd/system/rake-test:task.timer /var/lib/lxc/test/rootfs/etc/systemd/system/timers.target.wants/")
        subject.auto_start
      end
    end

    context 'with restart mode' do
      before do
        model.rake_mode = 'restart'
        model.rake_restart_on_touch = false
      end

      it 'should comment adding rake service' do
        expect(subject).to receive(:comment_sub_step).with('Add Rake service to runlevel default')
        subject.auto_start
      end

      it 'should create multi-user.target.wants directory' do
        expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants')
        subject.auto_start
      end

      it 'should link service to multi-user.target.wants' do
        expect(host).to receive(:exec).with("ln -sf /etc/systemd/system/rake-test:task.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
        subject.auto_start
      end
    end

    context 'with restart mode and rake_restart_on_touch' do
      before do
        model.rake_mode = 'restart'
        model.rake_restart_on_touch = true
      end

      it 'should render restart path unit' do
        expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/rake_restart.path', '/var/lib/lxc/test/rootfs/etc/systemd/system/rake-restart-test:task.path', 644, service: model)
        subject.auto_start
      end

      it 'should render restart service unit' do
        expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/rake_restart.service', '/var/lib/lxc/test/rootfs/etc/systemd/system/rake-restart-test:task.service', 644, service: model)
        subject.auto_start
      end

      it 'should link restart path to multi-user.target.wants' do
        expect(host).to receive(:exec).with("ln -sf /etc/systemd/system/rake-restart-test:task.path /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
        subject.auto_start
      end
    end

    context 'with single mode' do
      before do
        model.rake_mode = 'single'
        model.rake_restart_on_touch = false
      end

      it 'should use auto_start_service like restart mode' do
        expect(subject).to receive(:comment_sub_step).with('Add Rake service to runlevel default')
        subject.auto_start
      end
    end
  end
end