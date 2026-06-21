require 'spec_helper'

describe CloudModel::Workers::GuestWorker do
  let(:host) { Factory :host }
  let(:guest) { double CloudModel::Guest, host: host, name: 'test-guest', deploy_state: :pending, deploy_path: '/var/lib/lxd/containers/test/rootfs' }
  subject { CloudModel::Workers::GuestWorker.new guest }

  before do
    allow(host).to receive(:exec)
    allow(host).to receive(:exec!)
  end

  describe 'deploy' do
    it 'should return false if not pending and not forced' do
      allow(guest).to receive(:deploy_state).and_return(:finished)
      expect(subject.deploy).to eq false
    end

    it 'should run deployment steps when pending' do
      allow(guest).to receive(:deploy_state).and_return(:pending)
      allow(guest).to receive(:update_attributes)
      allow(guest).to receive(:collection).and_return(double(update_one: true))
      allow(guest).to receive(:id).and_return(BSON::ObjectId.new)
      allow(subject).to receive(:run_steps)
      allow(Rails.logger).to receive(:debug)
      lxc = double('lxc', name: 'test-lxc')
      subject.instance_variable_set(:@lxc, lxc)

      expect { subject.deploy }.to output(/Finished/).to_stdout
    end
  end

  describe 'redeploy' do
    it 'should delegate to deploy' do
      expect(subject).to receive(:deploy).with({force: true})
      subject.redeploy(force: true)
    end
  end

  describe 'umount_all' do
    it 'should respond to umount_all or equivalent' do
      expect(subject).to respond_to(:cleanup_chroot)
    end
  end

  describe 'mount_all' do
    it 'should respond to mount_all or equivalent' do
      expect(subject).to respond_to(:prepare_chroot)
    end
  end

  describe 'write_fs' do
    it 'should be inherited from BaseWorker' do
      expect(subject).to be_a CloudModel::Workers::BaseWorker
    end
  end

  describe 'mk_root_lv' do
    it 'should be inherited from BaseWorker' do
      expect(subject).to be_a CloudModel::Workers::BaseWorker
    end
  end

  describe 'mk_root_fs' do
    it 'should be inherited from BaseWorker' do
      expect(subject).to be_a CloudModel::Workers::BaseWorker
    end
  end

  describe 'mount_root_fs' do
    it 'should be inherited from BaseWorker' do
      expect(subject).to be_a CloudModel::Workers::BaseWorker
    end
  end

  describe 'unpack_root_image' do
    it 'should be inherited from BaseWorker' do
      expect(subject).to be_a CloudModel::Workers::BaseWorker
    end
  end

  describe 'config_guest' do
    it 'should be inherited from BaseWorker' do
      expect(subject).to be_a CloudModel::Workers::BaseWorker
    end
  end

  describe 'config_services' do
    it 'should configure each service' do
      lxc = double 'lxc', mountpoint: '/var/lib/lxd/containers/test'
      subject.instance_variable_set(:@lxc, lxc)
      allow(guest).to receive(:deploy_path=)
      allow(guest).to receive(:deploy_path).and_return("#{lxc.mountpoint}/rootfs")
      allow(guest).to receive(:services).and_return([])
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
      allow(host).to receive(:exec!)

      subject.config_services
    end
  end

  describe 'config_network' do
    it 'should render network config' do
      allow(guest).to receive(:deploy_path).and_return('/deploy')
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:chroot)

      subject.config_network
    end
  end

  describe 'config_firewall' do
    it 'should restart firewall' do
      allow(subject).to receive(:comment_sub_step)
      expect(host).to receive(:restart_firewall)

      subject.config_firewall
    end
  end

  describe 'activate_address_resolution' do
    it 'should activate resolution if present' do
      resolution = double 'resolution'
      allow(guest).to receive(:external_address_resolution).and_return(resolution)
      allow(guest).to receive(:external_hostname).and_return('test.example.com')
      expect(resolution).to receive(:update_attributes!).with(name: 'test.example.com', active: true)

      subject.activate_address_resolution
    end

    it 'should do nothing if no resolution' do
      allow(guest).to receive(:external_address_resolution).and_return(nil)

      subject.activate_address_resolution
    end
  end
end
