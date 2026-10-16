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

    it 'should leave the overlay root-owned (unshifted rootfs)' do
      expect(host).not_to receive(:exec).with(/chown/)
      subject.auto_start
    end
  end

  describe 'upload_to_guest' do
    let(:sftp_file) { double 'sftp file' }

    before do
      allow(lxc).to receive(:name).and_return 'test-20200331133742'
      allow(host).to receive(:sftp).and_return double('sftp', file: sftp_file)
      allow(sftp_file).to receive(:open).and_yield double('f', puts: nil)
      allow(host).to receive(:exec!)
      allow(BSON::ObjectId).to receive(:new).and_return 'tmpid'
    end

    it 'should push the content via lxc file push and remove the temp file' do
      expect(host).to receive(:exec!).with("lxc file push /tmp/cloudmodel_tmpid test-20200331133742//etc/motd -p --mode 0644", 'Failed to upload /etc/motd')
      expect(host).to receive(:exec).with('rm /tmp/cloudmodel_tmpid')
      allow(lxc).to receive(:mount)

      expect(subject.upload_to_guest 'hello', '/etc/motd', '0644').to eq true
    end

    it 'should remount the container afterwards — LXD unmounts a stopped container after the push' do
      expect(host).to receive(:exec!).ordered
      expect(lxc).to receive(:mount).ordered

      subject.upload_to_guest 'hello', '/etc/motd'
    end
  end
end