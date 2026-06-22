# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::Neo4jWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host, deploy_path: '/var/lib/lxc/test/rootfs'}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Neo4j.new}
  subject {CloudModel::Workers::Services::Neo4jWorker.new lxc, model}

  describe 'write_config' do
    let(:sftp_file) { double 'sftp_file' }
    let(:sftp) { double 'sftp', file: double('file', open: true) }

    before do
      allow(host).to receive(:sftp).and_return(sftp)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:render).and_return('rendered conf')
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Write neo4j config')
      subject.write_config
    end

    it 'should open the neo4j.conf file for writing in the deploy path' do
      expect(sftp.file).to receive(:open).with('/var/lib/lxc/test/rootfs/etc/neo4j/neo4j.conf', 'w')
      subject.write_config
    end

    it 'should render the neo4j.conf template' do
      file = double 'file'
      allow(sftp.file).to receive(:open).and_yield(file)
      expect(subject).to receive(:render).with('/cloud_model/guest/etc/neo4j/neo4j.conf', guest: guest, model: model).and_return('rendered conf')
      expect(file).to receive(:write).with('rendered conf')
      subject.write_config
    end
  end

  describe 'service_name' do
    it 'should return neo4j' do
      expect(subject.service_name).to eq 'neo4j'
    end
  end

  describe 'auto_restart' do
    it 'should return true' do
      expect(subject.auto_restart).to eq true
    end
  end

  describe 'auto_start' do
    before do
      allow(host).to receive(:exec)
      allow(host).to receive(:exec!)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
    end

    it 'should create the systemd drop-in overlay directory' do
      expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/systemd/system/neo4j.service.d')
      subject.auto_start
    end

    it 'should render the fix_perms.conf drop-in' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/neo4j.service.d/fix_perms.conf', '/var/lib/lxc/test/rootfs/etc/systemd/system/neo4j.service.d/fix_perms.conf')
      subject.auto_start
    end

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with('ln -sf /lib/systemd/system/neo4j.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/')
      subject.auto_start
    end

    it 'should write the restart drop-in since auto_restart is true' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/support/etc/systemd/unit.d/restart.conf', '/var/lib/lxc/test/rootfs/etc/systemd/system/neo4j.service.d/restart.conf', 644)
      subject.auto_start
    end
  end
end
