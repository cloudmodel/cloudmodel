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
      allow(guest).to receive(:services).and_return([])
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
    before do
      subject.instance_variable_set(:@lxc, double('lxc', name: 'test-lxc'))
      allow(guest).to receive(:deploy_path).and_return('/deploy')
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:chroot)
    end

    it 'should render network config' do
      subject.config_network
    end

    it 'should render hostname and hosts for the container' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/hostname', '/deploy/etc/hostname', container_name: 'test-lxc')
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/hosts', '/deploy/etc/hosts', container_name: 'test-lxc')

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

  describe 'accessors' do
    it 'should expose host' do
      expect(subject.host).to eq host
    end

    it 'should expose guest' do
      expect(subject.guest).to eq guest
    end

    it 'should use guest as error_log_object' do
      expect(subject.error_log_object).to eq guest
    end
  end

  describe 'mkdir_p' do
    it 'should create the dir and chown it to the container uid range' do
      expect(host).to receive(:exec!).with('mkdir -p /some/path', 'Failed to make directory /some/path')
      expect(host).to receive(:exec!).with('chown -R 100000:100000 /some/path', 'failed to set owner for /some/path')

      subject.mkdir_p '/some/path'
    end
  end

  describe 'render_to_remote' do
    it 'should render via super and chown the remote file to the container uid range' do
      sftp = double 'sftp'
      sftp_file = double 'sftp_file'
      allow(host).to receive(:sftp).and_return(sftp)
      allow(sftp).to receive(:file).and_return(sftp_file)
      allow(sftp_file).to receive(:open)
      allow(subject).to receive(:render).and_return('content')
      expect(host).to receive(:exec!).with('chown -R 100000:100000 /etc/foo', 'failed to set owner for /etc/foo')

      subject.render_to_remote '/cloud_model/some/template', '/etc/foo', guest: guest
    end
  end

  describe 'ensure_zfs_template' do
    let(:template) { double 'template' }
    let(:volume) { double CloudModel::BuildZfsVolume }

    before do
      allow(guest).to receive(:template).and_return(template)
      allow(template).to receive(:build_volume).with(host).and_return(volume)
    end

    it 'should do nothing when the template volume is ready on the host' do
      allow(volume).to receive(:ready?).and_return(true)
      expect(template).not_to receive(:ensure_build_volume!)

      subject.ensure_zfs_template
    end

    it 'should sync or build the template volume when missing on the host' do
      allow(volume).to receive(:ready?).and_return(false)
      allow(subject).to receive(:comment_sub_step)
      expect(template).to receive(:ensure_build_volume!).with(host)

      subject.ensure_zfs_template
    end
  end

  describe 'create_lxd_container' do
    it 'should create a container for the guest template, mount it and write the deploy stamp' do
      template = double 'template'
      subject.instance_variable_set(:@template, template)
      lxc = double 'lxc', name: 'test-lxc'
      lxd_containers = double 'lxd_containers'
      allow(guest).to receive(:lxd_containers).and_return(lxd_containers)
      expect(lxd_containers).to receive(:new).with(hash_including(guest_template: template)).and_return(lxc)
      expect(lxc).to receive(:save!)
      expect(lxc).to receive(:mount)
      expect(host).to receive(:exec!).with(/lxc file push - test-lxc\/etc\/deployed/, 'Failed to render deploy stemp')

      subject.create_lxd_container
      expect(subject.instance_variable_get(:@lxc)).to eq lxc
    end
  end

  describe 'mount_lxd_container' do
    it 'should look up the latest container and mount it' do
      lxc = double 'lxc', name: 'test-lxc', mountpoint: '/var/lib/lxd/storage-pools/default/containers/test-lxc'
      desc = double 'desc'
      allow(guest).to receive(:lxd_containers).and_return(double('containers', desc: desc))
      allow(desc).to receive(:first).and_return(lxc)
      expect(subject).to receive(:comment_sub_step).with('Mounting guests/containers/test-lxc to /var/lib/lxd/storage-pools/default/containers/test-lxc')
      expect(lxc).to receive(:mount)
      expect(host).to receive(:exec!).with(/lxc file push - test-lxc\/etc\/deployed.resume/, 'Failed to render deploy stemp')

      subject.mount_lxd_container
    end
  end

  describe 'ensure_lxd_custom_volumes' do
    it 'should create volumes that do not yet exist and skip existing ones' do
      missing = double 'missing_volume', volume_exists?: false
      existing = double 'existing_volume', volume_exists?: true
      allow(guest).to receive(:lxd_custom_volumes).and_return([missing, existing])
      expect(missing).to receive(:create_volume!)
      expect(existing).not_to receive(:create_volume!)

      subject.ensure_lxd_custom_volumes
    end
  end

  describe 'config_lxd_container' do
    it 'should configure the container from the guest' do
      lxc = double 'lxc'
      subject.instance_variable_set(:@lxc, lxc)
      expect(lxc).to receive(:config_from_guest)

      subject.config_lxd_container
    end
  end

  describe 'start_lxd_container' do
    it 'should cleanup chroot, unmount, set booting and restart the guest' do
      lxc = double 'lxc'
      subject.instance_variable_set(:@lxc, lxc)
      allow(guest).to receive(:deploy_path).and_return('/deploy/')
      expect(subject).to receive(:cleanup_chroot).with('/deploy/')
      expect(lxc).to receive(:unmount)
      expect(guest).to receive(:update_attributes).with(deploy_state: :booting)
      expect(guest).to receive(:stop)
      expect(guest).to receive(:start).with(lxc)

      subject.start_lxd_container
    end
  end

  describe 'config_services error handling' do
    it 'should raise a wrapped error when a service worker fails' do
      service = double 'service'
      allow(service).to receive_message_chain(:class, :model_name, :element).and_return('nginx')
      allow(service).to receive(:name).and_return('web')
      lxc = double 'lxc', mountpoint: '/mp'
      subject.instance_variable_set(:@lxc, lxc)
      allow(guest).to receive(:deploy_path=)
      allow(guest).to receive(:deploy_path).and_return('/mp/rootfs')
      allow(guest).to receive(:services).and_return([service])
      allow(subject).to receive(:comment_sub_step)
      allow(CloudModel).to receive(:log_exception)
      # Constantizing the worker class will fail for the bogus service name
      allow($stdout).to receive(:puts)

      expect { subject.config_services }.to raise_error(/Failed to configure service/)
    end
  end

  describe 'config_guest_certificates' do
    let(:sftp) { double 'sftp' }
    let(:sftp_file) { double 'sftp_file' }
    let(:file_handle) { double 'file_handle' }

    before do
      allow(host).to receive(:sftp).and_return(sftp)
      allow(sftp).to receive(:file).and_return(sftp_file)
      allow(sftp_file).to receive(:open).and_yield(file_handle)
      allow(file_handle).to receive(:write)
      allow(subject).to receive(:mkdir_p)
      allow(guest).to receive(:deploy_path).and_return('/deploy')
    end

    it 'should write crt and key files and set ownership/permissions' do
      certificate = double 'certificate', crt: 'CRT', key: 'KEY'
      cert = double 'cert', path_to_crt: '/etc/ssl/cert.crt', path_to_key: '/etc/ssl/cert.key', certificate: certificate
      allow(guest).to receive(:guest_certificates).and_return([cert])

      expect(sftp_file).to receive(:open).with('/deploy/etc/ssl/cert.crt', 'w').and_yield(file_handle)
      expect(sftp_file).to receive(:open).with('/deploy/etc/ssl/cert.key', 'w').and_yield(file_handle)
      expect(host).to receive(:exec!).with('chown 100000:100000 /deploy/etc/ssl/cert.crt', 'failed to set owner for /deploy/etc/ssl/cert.crt')
      expect(host).to receive(:exec!).with('chown 100000:100000 /deploy/etc/ssl/cert.key', 'failed to set owner for /deploy/etc/ssl/cert.key')
      expect(host).to receive(:exec!).with('chmod 0700 /deploy/etc/ssl/cert.key', 'failed to limit rights for /deploy/etc/ssl/cert.key')

      subject.config_guest_certificates
    end

    it 'should skip cert/key when their paths are blank' do
      cert = double 'cert', path_to_crt: '', path_to_key: ''
      allow(guest).to receive(:guest_certificates).and_return([cert])
      expect(sftp_file).not_to receive(:open)

      subject.config_guest_certificates
    end
  end

  describe 'deploy error handling' do
    it 'should cleanup chroot, unmount lxc and re-raise on failure' do
      allow(guest).to receive(:deploy_state).and_return(:pending)
      allow(guest).to receive(:update_attributes)
      allow(guest).to receive(:deploy_path).and_return('/deploy')
      lxc = double 'lxc', blank?: false
      subject.instance_variable_set(:@lxc, lxc)
      allow(subject).to receive(:run_steps).and_raise('boom')
      expect(subject).to receive(:cleanup_chroot).with('/deploy')
      expect(lxc).to receive(:unmount)

      expect { subject.deploy }.to raise_error('boom')
    end
  end
end
