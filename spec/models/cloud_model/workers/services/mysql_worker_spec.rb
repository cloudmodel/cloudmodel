# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::MysqlWorker do
  let(:host) { double CloudModel::Host }
  let(:guest) { double CloudModel::Guest, host: host, deploy_path: '/var/lib/lxc/test/rootfs' }
  let(:lxc) { double CloudModel::LxdContainer, guest: guest }
  let(:model) { CloudModel::Services::Mysql.new }
  subject { CloudModel::Workers::Services::MysqlWorker.new lxc, model }

  it { expect(subject.service_name).to eq 'mysql' }

  describe 'write_config' do
    before do
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:render_to_guest)
      allow(host).to receive(:exec!)
    end

    it 'should render the server options' do
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/mysql/mysql.conf.d/zz-cloudmodel.cnf', '/etc/mysql/mysql.conf.d/zz-cloudmodel.cnf', 0644, guest: guest, model: model)
      subject.write_config
    end

    it 'should mask the telemetry agent by default' do
      expect(host).to receive(:exec!).with('rm -f /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/percona-telemetry-agent.service && ln -sf /dev/null /var/lib/lxc/test/rootfs/etc/systemd/system/percona-telemetry-agent.service', 'Failed to mask percona telemetry agent')
      subject.write_config
    end

    it 'should leave the telemetry agent alone for MySQL Community' do
      model.mysql_distribution = 'mysql'
      expect(host).not_to receive(:exec!)
      subject.write_config
    end

    it 'should enable the telemetry agent with telemetry' do
      model.telemetry = true
      expect(host).to receive(:exec!).with('rm -f /var/lib/lxc/test/rootfs/etc/systemd/system/percona-telemetry-agent.service && ln -sf /lib/systemd/system/percona-telemetry-agent.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/percona-telemetry-agent.service', 'Failed to enable percona telemetry agent')
      subject.write_config
    end
  end

  describe 'auto_start' do
    before do
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
      allow(host).to receive(:exec)
    end

    it 'should render the drop-in and enable mysql' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/mysql.service.d/cloudmodel.conf', '/var/lib/lxc/test/rootfs/etc/systemd/system/mysql.service.d/cloudmodel.conf', 0644, model: model)
      expect(host).to receive(:exec).with('ln -sf /lib/systemd/system/mysql.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/')
      subject.auto_start
    end
  end
end
