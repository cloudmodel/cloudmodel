# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::RedisWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Redis.new}
  subject {CloudModel::Workers::Services::RedisWorker.new lxc, model}

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

    it 'should write redis.conf' do
      expect(sftp_file).to receive(:open).with('/var/lib/lxc/test/rootfs/etc/redis/redis.conf', 'w')
      subject.write_config
    end

    it 'should render redis config template' do
      expect(subject).to receive(:render).with('/cloud_model/guest/etc/redis/redis.conf', guest: guest, model: model)
      subject.write_config
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Write redis config')
      subject.write_config
    end

    context 'with sentinel set' do
      before do
        allow(model).to receive(:redis_sentinel_set_id).and_return('some_sentinel_id')
      end

      it 'should write sentinel.conf' do
        expect(sftp_file).to receive(:open).with('/var/lib/lxc/test/rootfs/etc/redis/sentinel.conf', 'w')
        subject.write_config
      end

      it 'should render sentinel config template' do
        expect(subject).to receive(:render).with('/cloud_model/guest/etc/redis/sentinel.conf', guest: guest, model: model)
        subject.write_config
      end
    end

    context 'without sentinel set' do
      before do
        allow(model).to receive(:redis_sentinel_set_id).and_return(nil)
      end

      it 'should not write sentinel.conf' do
        expect(sftp_file).not_to receive(:open).with('/var/lib/lxc/test/rootfs/etc/redis/sentinel.conf', 'w')
        subject.write_config
      end
    end
  end

  describe 'service_name' do
    it 'should return redis-server' do
      expect(subject.service_name).to eq 'redis-server'
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

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Add Redis Services to runlevel default')
      subject.auto_start
    end

    it 'should link redis_server service to multi-user.target.wants' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/redis_server.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should create redis_server overlay directory' do
      expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/systemd/system/redis_server.service.d')
      subject.auto_start
    end

    it 'should render restart drop-in for redis_server' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/support/etc/systemd/unit.d/restart.conf', '/var/lib/lxc/test/rootfs/etc/systemd/system/redis_server.service.d/restart.conf')
      subject.auto_start
    end

    it 'should chown redis_server overlay path' do
      expect(host).to receive(:exec).with('chown -R 100000:100000 /var/lib/lxc/test/rootfs/etc/systemd/system/redis_server.service.d')
      subject.auto_start
    end

    context 'with sentinel set' do
      before do
        allow(model).to receive(:redis_sentinel_set_id).and_return('some_sentinel_id')
      end

      it 'should link redis_sentinel service to multi-user.target.wants' do
        expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/redis_sentinel.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
        subject.auto_start
      end

      it 'should create redis_sentinel overlay directory' do
        expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/systemd/system/redis_sentinel.service.d')
        subject.auto_start
      end

      it 'should render restart drop-in for redis_sentinel' do
        expect(subject).to receive(:render_to_remote).with('/cloud_model/support/etc/systemd/unit.d/restart.conf', '/var/lib/lxc/test/rootfs/etc/systemd/system/redis_sentinel.service.d/restart.conf')
        subject.auto_start
      end

      it 'should chown redis_sentinel overlay path' do
        expect(host).to receive(:exec).with('chown -R 100000:100000 /var/lib/lxc/test/rootfs/etc/systemd/system/redis_sentinel.service.d')
        subject.auto_start
      end
    end

    context 'without sentinel set' do
      before do
        allow(model).to receive(:redis_sentinel_set_id).and_return(nil)
      end

      it 'should not link redis_sentinel service' do
        expect(host).not_to receive(:exec).with("ln -sf /lib/systemd/system/redis_sentinel.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
        subject.auto_start
      end
    end
  end
end