require 'spec_helper'

describe CloudModel::Workers::Services::MongodbWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Mongodb.new}
  subject {CloudModel::Workers::Services::MongodbWorker.new lxc, model}

  describe 'write_config' do
    let(:sftp_file) {double 'SftpFile'}
    let(:sftp) {double 'Sftp', file: sftp_file}

    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(host).to receive(:sftp).and_return(sftp)
      allow(subject).to receive(:render).and_return('rendered_config')
      allow(subject).to receive(:comment_sub_step)
      allow(sftp_file).to receive(:open).and_yield(double('file', write: true))
    end

    it 'should write mongod.conf' do
      expect(sftp_file).to receive(:open).with('/var/lib/lxc/test/rootfs/etc/mongod.conf', 'w')
      subject.write_config
    end

    it 'should render mongodb config template' do
      expect(subject).to receive(:render).with('/cloud_model/guest/etc/mongodb_conf', guest: guest, model: model)
      subject.write_config
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Write mongodb config')
      subject.write_config
    end
  end

  describe 'apply_wiredtiger_cache_live!' do
    before do
      allow(subject).to receive(:render).and_return('rendered_config')
      allow(subject).to receive(:upload_to_guest)
    end

    it 'rewrites mongod.conf in the running container and resizes the cache in place' do
      expect(subject).to receive(:upload_to_guest).with('rendered_config', '/etc/mongod.conf', '0644').ordered
      expect(model).to receive(:set_runtime_wiredtiger_cache!).ordered.and_return true
      expect(guest).not_to receive(:exec!)

      expect(subject.apply_wiredtiger_cache_live!).to eq :live
    end

    it 'raises when mongod refuses and no restart is allowed' do
      allow(model).to receive(:set_runtime_wiredtiger_cache!).and_raise('not allowed')
      expect(guest).not_to receive(:exec!)
      expect { subject.apply_wiredtiger_cache_live! }.to raise_error('not allowed')
    end

    it 'steps a primary down before restarting it when mongod refuses and restart is allowed' do
      allow(model).to receive(:set_runtime_wiredtiger_cache!).and_raise('not allowed')
      allow(CloudModel).to receive(:log_exception)
      allow(model).to receive(:mongodb_replication_set).and_return double('rs')
      allow(model).to receive(:running_primary?).and_return true
      allow(model).to receive(:guest).and_return guest
      expect(guest).to receive(:exec).with(/rs\.stepDown/).ordered
      expect(guest).to receive(:exec!).with('/bin/systemctl restart mongod', anything).ordered

      expect(subject.apply_wiredtiger_cache_live!(restart: true)).to eq :restarted
    end
  end

  describe 'service_name' do
    it 'should return mongodb' do
      expect(subject.service_name).to eq 'mongod'
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

    it 'should create overlay directory' do
      expect(subject).to receive(:mkdir_p).with(subject.overlay_path)
      subject.auto_start
    end

    it 'should render fix_perms.conf drop-in' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/mongodb_service_d/fix_perms_conf', "#{subject.overlay_path}/fix_perms.conf")
      subject.auto_start
    end

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/mongod.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should write restart drop-in since auto_restart is true' do
      expect(subject).to receive(:render_to_remote).with("/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{subject.overlay_path}/restart.conf", 644)
      subject.auto_start
    end
  end
end