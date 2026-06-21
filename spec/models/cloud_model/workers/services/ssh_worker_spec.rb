require 'spec_helper'

describe CloudModel::Workers::Services::SshWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Ssh.new}
  subject {CloudModel::Workers::Services::SshWorker.new lxc, model}

  describe 'write_config' do
    let(:sftp_file) {double 'SftpFile'}
    let(:sftp) {double 'Sftp', file: sftp_file}
    let(:sftp_dir) {double 'SftpDir'}

    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(guest).to receive(:private_address).and_return('10.42.0.1')
      allow(host).to receive(:sftp).and_return(sftp)
      allow(host).to receive(:exec)
      allow(host).to receive(:exec!)
      allow(subject).to receive(:render).and_return('rendered_config')
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:chroot!)
      allow(sftp_file).to receive(:open).and_yield(double('file', write: true))
      allow(sftp).to receive(:lstat!).and_raise(Net::SFTP::StatusException.new(double(code: 2, message: 'no such file')))
      allow(sftp).to receive(:dir).and_return(sftp_dir)
      allow(sftp_dir).to receive(:glob).and_return([])
    end

    it 'should write sshd_config' do
      expect(sftp_file).to receive(:open).with('/var/lib/lxc/test/rootfs/etc/ssh/sshd_config', 'w')
      subject.write_config
    end

    it 'should render sshd_config template' do
      expect(subject).to receive(:render).with('/cloud_model/guest/etc/ssh/sshd_config', guest: guest, model: model)
      subject.write_config
    end

    it 'should create ssh host key source directory' do
      expect(subject).to receive(:mkdir_p).with('/inst/hosts_by_ip/10.42.0.1/etc/ssh')
      subject.write_config
    end

    it 'should generate missing host keys' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', "ssh-keygen -t dsa -f /etc/ssh/ssh_host_dsa_key -N ''", 'Failed to generate host keys')
      subject.write_config
    end

    it 'should copy host keys to deploy path' do
      expect(host).to receive(:exec!).with('cp -ra /inst/hosts_by_ip/10.42.0.1/etc/ssh /var/lib/lxc/test/rootfs/etc', 'Failed to copy host keys')
      subject.write_config
    end

    it 'should set owner of server keys to root' do
      expect(host).to receive(:exec!).with('chown -R 100000:100000 /var/lib/lxc/test/rootfs/etc/ssh', 'Failed to change owner of server keys to user root')
      subject.write_config
    end

    it 'should set owner of www client keys' do
      expect(host).to receive(:exec!).with('chown -R 101001:101001 /var/lib/lxc/test/rootfs/var/www/.ssh', 'Failed to change owner of www client keys to user www')
      subject.write_config
    end
  end

  describe 'service_name' do
    it 'should return sshd' do
      expect(subject.service_name).to eq 'sshd'
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
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
    end

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/sshd.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should write restart drop-in since auto_restart is true' do
      expect(subject).to receive(:mkdir_p).with(subject.overlay_path)
      expect(subject).to receive(:render_to_remote).with("/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{subject.overlay_path}/restart.conf", 644)
      subject.auto_start
    end
  end
end