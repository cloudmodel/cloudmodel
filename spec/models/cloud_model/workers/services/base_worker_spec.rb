require 'spec_helper'

describe CloudModel::Workers::Services::BaseWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host, deploy_path: '/var/lib/lxc/test/rootfs'}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {double 'ServiceModel', class: CloudModel::Services::Ssh}
  subject {CloudModel::Workers::Services::BaseWorker.new lxc, model}

  before do
    allow(subject).to receive(:comment_sub_step)
    allow(subject).to receive(:mkdir_p)
    allow(subject).to receive(:render_to_remote)
    allow(host).to receive(:exec)
  end

  describe 'auto_start' do
    it 'should add service to runlevel default' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/ssh.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with("Add SSH Service to runlevel default")
      subject.auto_start
    end

    it 'should not write restart drop-in when auto_restart is false' do
      allow(subject).to receive(:auto_restart).and_return(false)
      expect(subject).not_to receive(:render_to_remote).with("/cloud_model/support/etc/systemd/unit.d/restart.conf", anything, anything)
      subject.auto_start
    end

    it 'should write restart drop-in when auto_restart is true' do
      allow(subject).to receive(:auto_restart).and_return(true)
      expect(subject).to receive(:mkdir_p).with(subject.overlay_path)
      expect(subject).to receive(:render_to_remote).with("/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{subject.overlay_path}/restart.conf", 644)
      subject.auto_start
    end

    it 'should chown overlay_path' do
      expect(host).to receive(:exec).with("chown -R 100000:100000 #{subject.overlay_path}")
      subject.auto_start
    end
  end
end