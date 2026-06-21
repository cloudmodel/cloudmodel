# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::BackupWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Backup.new}
  subject {CloudModel::Workers::Services::BackupWorker.new lxc, model}

  describe 'write_config' do
    it 'should be a no-op' do
      expect { subject.write_config }.not_to raise_error
    end
  end

  describe 'service_name' do
    it 'should return backup' do
      expect(subject.service_name).to eq 'backup'
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

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Add Rake timer to runlevel default')
      subject.auto_start
    end

    it 'should create timers.target.wants directory' do
      expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/systemd/system/timers.target.wants')
      subject.auto_start
    end

    it 'should render rake timer unit for backup task' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/rake.timer', '/var/lib/lxc/test/rootfs/etc/systemd/system/rake-cloudmodel:guest:backup_all.timer', 644, service: an_instance_of(CloudModel::Services::Rake))
      subject.auto_start
    end

    it 'should render rake service unit for backup task' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/rake.service', '/var/lib/lxc/test/rootfs/etc/systemd/system/rake-cloudmodel:guest:backup_all.service', 644, service: an_instance_of(CloudModel::Services::Rake))
      subject.auto_start
    end

    it 'should link timer to timers.target.wants' do
      expect(host).to receive(:exec).with("ln -sf /etc/systemd/system/rake-cloudmodel:guest:backup_all.timer /var/lib/lxc/test/rootfs/etc/systemd/system/timers.target.wants/")
      subject.auto_start
    end

    it 'should create rake service with correct timer configuration' do
      # Verify the Rake service is instantiated with the expected backup parameters
      expect(subject).to receive(:render_to_remote).with(
        '/cloud_model/guest/etc/systemd/system/rake.timer',
        anything, anything,
        service: having_attributes(
          rake_task: 'cloudmodel:guest:backup_all',
          rake_timer_on_boot: true,
          rake_timer_on_boot_sec: 900,
          rake_timer_on_calendar: true,
          rake_timer_on_calendar_val: '00:00',
          rake_timer_accuracy_sec: 600,
          rake_timer_persistent: false
        )
      )
      subject.auto_start
    end
  end
end