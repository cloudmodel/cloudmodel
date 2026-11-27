# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::FleetWorker do
  let(:host) { double CloudModel::Host }
  let(:guest) { double CloudModel::Guest, host: host, deploy_path: '/var/lib/lxc/test/rootfs' }
  let(:lxc) { double CloudModel::LxdContainer, guest: guest }
  let(:model) { CloudModel::Services::Fleet.new }
  subject { CloudModel::Workers::Services::FleetWorker.new lxc, model }

  describe 'write_config' do
    before do
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:chroot!)
      allow(subject).to receive(:render_to_guest)
      allow(host).to receive(:exec!)
      allow(model).to receive(:save).and_return true
    end

    it 'should generate and save missing secrets' do
      expect(model).to receive(:save)
      subject.write_config
      expect(model.enroll_secret).to be_present
    end

    it 'should raise instead of rendering secrets the database does not hold' do
      allow(model).to receive(:save).and_return false
      allow(model).to receive_message_chain(:errors, :full_messages).and_return ['Admin email can\'t be blank']
      expect(subject).not_to receive(:render_to_guest)

      expect { subject.write_config }.to raise_error(/Could not store the generated Fleet secrets: Admin email/)
    end

    it 'should not save when all secrets are present' do
      model.generate_secrets
      expect(model).not_to receive(:save)
      subject.write_config
    end

    it 'should render the fleet config readable by the service user and the root-only scripts' do
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/fleet/fleet.yml', '/etc/fleet/fleet.yml', 0640, guest: guest, model: model)
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/fleet/prepare_db.sh', '/etc/fleet/prepare_db.sh', 0700, guest: guest, model: model)
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/fleet/provision.sh', '/etc/fleet/provision.sh', 0700, guest: guest, model: model)
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/fleet/provision.yml', '/etc/fleet/provision.yml', 0600, guest: guest, model: model)
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', /chown root:fleet \/etc\/fleet\/fleet.yml && chmod 640/, 'Failed to set fleet config ownership')
      subject.write_config
    end

    it 'should leave the database server alone' do
      expect(subject).not_to receive(:render_to_guest).with(%r{mysql}, any_args)
      expect(host).not_to receive(:exec!)
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

    it 'should prepare the database before every fleet start' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/fleet.service.d/prepare_db.conf', '/var/lib/lxc/test/rootfs/etc/systemd/system/fleet.service.d/prepare_db.conf', 0644)
      subject.auto_start
    end

    it 'should enable fleet and the provisioning unit' do
      expect(host).to receive(:exec).with('ln -sf /etc/systemd/system/fleet_provision.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/')
      expect(host).to receive(:exec).with('ln -sf /lib/systemd/system/fleet.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/')
      subject.auto_start
    end
  end
end
