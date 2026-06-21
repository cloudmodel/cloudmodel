# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::SolrWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest, name: 'test-container'}
  let(:model) {CloudModel::Services::Solr.new}
  subject {CloudModel::Workers::Services::SolrWorker.new lxc, model}

  describe 'write_config' do
    let(:sftp) {double 'Sftp'}
    let(:solr_mirror) {double 'SolrMirror', file: double('MirrorFile', data: 'mirror_data')}
    let(:solr_image) {double 'SolrImage', name: 'test-config', solr_version: '9.0.0', solr_mirror: solr_mirror, file: double('ImageFile', data: 'image_data')}

    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(host).to receive(:sftp).and_return(sftp)
      allow(host).to receive(:exec)
      allow(host).to receive(:exec!)
      allow(model).to receive(:deploy_solr_image).and_return(solr_image)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_guest)
      allow(sftp).to receive(:upload!)
      allow(sftp).to receive(:remove!)
    end

    it 'should comment deploying solr mirror' do
      expect(subject).to receive(:comment_sub_step).with('Deploy SOLR Mirror 9.0.0')
      subject.write_config
    end

    it 'should upload solr mirror tarball' do
      expect(sftp).to receive(:upload!).with(instance_of(StringIO), '/tmp/opt.tar.bz2')
      subject.write_config
    end

    it 'should extract solr mirror' do
      expect(host).to receive(:exec).with('cd /tmp/opt && tar xzpf /tmp/opt.tar.bz2')
      subject.write_config
    end

    it 'should create symlink to solr version' do
      expect(host).to receive(:exec!).with('rm /tmp/opt/solr; ln -s /opt/solr-9.0.0 /tmp/opt/solr', 'Failed to create link to solr version')
      subject.write_config
    end

    it 'should push solr mirror to container' do
      expect(host).to receive(:exec!).with("lxc file push /tmp/opt/ #{lxc.name}/ -p -r && rm -rf /tmp/opt", 'Failed to upload SOLR Mirror to container')
      subject.write_config
    end

    it 'should comment deploying solr config' do
      expect(subject).to receive(:comment_sub_step).with('Deploy SOLR Config test-config')
      subject.write_config
    end

    it 'should upload solr config tarball' do
      expect(sftp).to receive(:upload!).with(instance_of(StringIO), '/tmp/solr.tar.bz2')
      subject.write_config
    end

    it 'should create log, cache and data directories' do
      expect(subject).to receive(:mkdir_p).with('/tmp/solr/log')
      expect(subject).to receive(:mkdir_p).with('/tmp/solr/cache')
      expect(subject).to receive(:mkdir_p).with('/tmp/solr/data')
      subject.write_config
    end

    it 'should set ownership on solr config' do
      expect(host).to receive(:exec!).with('chown -R 100999:100999  /tmp/solr', 'Failed to setup rights')
      subject.write_config
    end

    it 'should push solr config to container' do
      expect(host).to receive(:exec!).with("lxc file push /tmp/solr/ #{lxc.name}/var/ -p -r && rm -rf /tmp/solr", 'Failed to upload SOLR Config to container')
      subject.write_config
    end

    it 'should render systemd service unit' do
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/systemd/system/solr.service', '/etc/systemd/system/solr.service', 0755, guest: guest, model: model)
      subject.write_config
    end
  end

  describe 'service_name' do
    it 'should return solr' do
      expect(subject.service_name).to eq 'solr'
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

    it 'should create overlay directory' do
      expect(subject).to receive(:mkdir_p).with(subject.overlay_path)
      subject.auto_start
    end

    it 'should render fix_perms.conf drop-in' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/solr.service.d/fix_perms.conf', "#{subject.overlay_path}/fix_perms.conf")
      subject.auto_start
    end

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/solr.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end
  end
end