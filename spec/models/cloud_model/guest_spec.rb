# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Guest do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to belong_to(:host).of_type CloudModel::Host }
  it { expect(subject).to embed_many(:services).of_type CloudModel::Services::Base }
  it { expect(subject).to embed_many(:lxd_containers).of_type CloudModel::LxdContainer }
  it { expect(subject).to embed_many(:lxd_custom_volumes).of_type CloudModel::LxdCustomVolume }
  it { expect(subject).to have_field(:current_lxd_container_id).of_type BSON::ObjectId }
  it { expect(subject).to have_many(:guest_certificates).of_type CloudModel::GuestCertificate}

  it { expect(subject).to have_field(:os_version).of_type(String).with_default_value_of "ubuntu-#{CloudModel.config.ubuntu_version}" }
  it { expect(subject).to have_field(:name).of_type String }

  it { expect(subject).to have_field(:private_address).of_type String }
  it { expect(subject).to have_field(:external_address).of_type String }
  it { expect(subject).to have_field(:mac_address).of_type String }
  it { expect(subject).to have_field(:external_alt_names).of_type(Array).with_default_value_of [] }

  it { expect(subject).to have_field(:root_fs_size).of_type(Integer).with_default_value_of 10*1024*1024*1024 }
  it { expect(subject).to have_field(:memory_size).of_type(Integer).with_default_value_of 2*1024*1024*1024 }
  it { expect(subject).to have_field(:cpu_count).of_type(Integer).with_default_value_of 2 }

  it { expect(subject).to have_field(:lxd_autostart_priority).of_type(Integer).with_default_value_of 50 }
  it { expect(subject).to have_field(:lxd_autostart_delay).of_type(Integer).with_default_value_of 0 }

  it { expect(subject).to have_enum(:deploy_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0xe0 => :booting,
    0xf0 => :finished,
    0xf1 => :failed,
    0xff => :not_started
  ).with_default_value_of(:not_started) }

  it { expect(subject).to have_field(:deploy_last_issue).of_type String }
  it { expect(subject).to have_field(:last_deploy_finished_at).of_type Time }
  it { expect(subject).to have_field(:deploy_path).of_type String }

  it { expect(subject).to have_enum(:up_state).with_values(
    0x00 => :started,
    0x01 => :stopped,
    0x40 => :booting,
    0x41 => :start_failed,
    0xff => :not_deployed_yet
  ).with_default_value_of(:not_deployed_yet) }
  it { expect(subject).to have_field(:last_downtime_at).of_type Time }
  it { expect(subject).to have_field(:last_downtime_reason).of_type String }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name).scoped_to(:host) }
  it { expect(subject).to validate_format_of(:name).to_allow("host-name-01") }
  it { expect(subject).to validate_format_of(:name).not_to_allow("Test Host") }

  it { expect(subject).to validate_presence_of(:host) }
  it { expect(subject).to validate_presence_of(:private_address) }

  it { expect(subject).to validate_presence_of(:lxd_autostart_priority) }
  it { expect(subject).to validate_numericality_of(:lxd_autostart_priority).greater_than_or_equal_to 0 }
  it { expect(subject).to validate_presence_of(:lxd_autostart_delay) }
  it { expect(subject).to validate_numericality_of(:lxd_autostart_delay).greater_than_or_equal_to 0 }

  let(:host) { Factory.build :host }

  describe 'root_fs_size=' do
    it 'should parse input as size string' do
      expect(subject).to receive(:accept_size_string_parser).with('Size String').and_return(23)
      subject.root_fs_size = 'Size String'

      expect(subject.root_fs_size).to eq 23
    end
  end

  describe 'memory_size=' do
    it 'should parse input as size string' do
      expect(subject).to receive(:accept_size_string_parser).with('Size String').and_return(42)
      subject.memory_size = 'Size String'

      expect(subject.memory_size).to eq 42
    end
  end

  describe 'current_lxd_container' do
    it 'should get lxd_container with current_lxd_container_id' do
      container = double CloudModel::LxdContainer
      current_container_id = BSON::ObjectId.new
      subject.current_lxd_container_id = current_container_id
      expect(subject.lxd_containers).to receive(:where).with(id: current_container_id).and_return [container]

      expect(subject.current_lxd_container).to eq container
    end
  end

  describe 'available_private_address_collection' do
    it 'should return host´s available_private_address_collection and add it´s own private address' do
      subject.host = host
      expect(host).to receive(:available_private_address_collection).and_return(['10.42.42.4', '10.42.42.6'])
      subject.private_address = '10.42.42.12'
      expect(subject.available_private_address_collection).to eq [
        '10.42.42.12',
        '10.42.42.4',
        '10.42.42.6'
      ]
    end
  end

  describe 'available_external_address_collection' do
    it 'should return host´s available_external_address_collection and add it´s own external address' do
      subject.host = host
      expect(host).to receive(:available_external_address_collection).and_return(['192.168.42.4', '192.168.42.6'])
      subject.external_address = '192.168.42.12'
      expect(subject.available_external_address_collection).to eq [
        '192.168.42.12',
        '192.168.42.4',
        '192.168.42.6'
      ]
    end
  end

  describe 'external_hostname' do
    it 'should lookup the hostname for the external ip' do
      allow(Resolv).to receive(:getname).with('127.0.0.1').and_return('localhost')
      subject.external_address = '127.0.0.1'
      expect(subject.external_hostname).to eq 'localhost'
    end

    it 'should return the raw ip if lookup fails' do
      allow(Resolv).to receive(:getname).with('127.0.0.1').and_raise('DNS not available')
      subject.external_address = '127.0.0.1'
      expect(subject.external_hostname).to eq '127.0.0.1'
    end
  end

  describe '#external_hostname' do
    it 'should return blank string if no external address' do
      expect(subject.external_hostname).to eq ''
    end

    it 'should get hostname for external address via Address' do
      address = double CloudModel::Address
      allow(CloudModel::Address).to receive(:from_str).with('198.51.100.42').and_return address
      allow(address).to receive(:hostname).and_return 'myhost.example.com'

      subject.external_address = '198.51.100.42'
      expect(subject.external_hostname).to eq 'myhost.example.com'
    end

    it 'should set instance variable' do
      address = double CloudModel::Address
      allow(CloudModel::Address).to receive(:from_str).with('198.51.100.42').and_return address
      allow(address).to receive(:hostname).and_return 'myhost.example.com'

      subject.external_address = '198.51.100.42'
      subject.external_hostname
      expect(subject.instance_variable_get :@external_hostname).to eq 'myhost.example.com'
    end

    it 'should get instance variable if set' do
      subject.instance_variable_set :@external_hostname, 'test.example.com'
      expect(subject.external_hostname).to eq 'test.example.com'
    end
  end

  describe '#external_host_name=' do
    it 'should set instance variable' do
      subject.external_hostname = 'test.example.com'
      expect(subject.instance_variable_get :@external_hostname).to eq 'test.example.com'
    end

    it 'should set changed instance variable if hostname changed' do
      expect(subject.instance_variable_get :@external_hostname_changed).not_to eq true
      subject.external_hostname = 'test.example.com'
      expect(subject.instance_variable_get :@external_hostname_changed).to eq true
    end

    it 'should not set changed instance variable if hostname did not changed' do
      subject.instance_variable_set :@external_hostname, 'test.example.com'
      subject.instance_variable_set :@external_hostname_changed, false
      subject.external_hostname = 'test.example.com'
      expect(subject.instance_variable_get :@external_hostname_changed).to eq false
    end
  end

  describe '#external_address_resolution' do
    it 'should find or init AddressResolution with external address given' do
      resolution = double
      subject.external_address = '198.51.100.42'
      expect(CloudModel::AddressResolution).to receive(:find_or_initialize_by).with(ip: '198.51.100.42').and_return resolution
      expect(subject.external_address_resolution).to eq resolution
    end

    it 'should return nil with no external address given' do
      subject.external_address = nil
      expect(CloudModel::AddressResolution).not_to receive(:find_or_initialize_by)
      expect(subject.external_address_resolution).to eq nil
    end
  end

  describe '#apply_address_resolution' do
    it 'should set AddressResolution if yield was successful, guest has external address and external hostname changed' do
      resolution = double
      subject.external_address = '198.51.100.42'
      subject.external_hostname = 'test42.example.com'

      expect(subject).to receive(:external_address_resolution).and_return resolution
      expect(resolution).to receive(:update_attributes).with(name: 'test42.example.com', alt_names: [])
      subject.apply_address_resolution{true}
    end

    it 'should set AddressResolution if yield was successful, guest has external address and external hostname and alt_names changed' do
      resolution = double
      subject.external_address = '198.51.100.42'
      subject.external_hostname = 'test42.example.com'
      subject.external_alt_names = ['test23.example.com', 'production.example.com']

      expect(subject).to receive(:external_address_resolution).and_return resolution
      expect(resolution).to receive(:update_attributes).with(name: 'test42.example.com', alt_names: ['test23.example.com', 'production.example.com'])
      subject.apply_address_resolution{true}
    end

    it 'should set external hostname changed to false' do
      subject.external_address = '198.51.100.42'
      allow(subject).to receive(:external_address_resolution).and_return double update_attributes: true
      subject.instance_variable_set :@external_hostname_changed, true

      subject.apply_address_resolution{true}
      expect(subject.instance_variable_get :@external_hostname_changed).to eq false
    end

    it 'should do nothing if yield failed' do
      subject.external_address = '198.51.100.42'
      subject.external_hostname = 'test42.example.com'
      subject.external_alt_names = ['test23.example.com', 'production.example.com']

      expect(subject).not_to receive(:external_address_resolution)
      subject.instance_variable_set :@external_hostname_changed, true
      subject.apply_address_resolution{false}
      expect(subject.instance_variable_get :@external_hostname_changed).to eq true
    end

    it 'should do nothing if external hostname did not change' do
      subject.external_address = '198.51.100.42'
      subject.external_hostname = 'test42.example.com'
      subject.external_alt_names = []

      expect(subject).not_to receive(:external_address_resolution)
      subject.instance_variable_set :@external_hostname_changed, false
      subject.apply_address_resolution{true}
    end

    it 'should set AddressResolution if external hostname did not change, but external alt names' do
      resolution = double
      subject.external_address = '198.51.100.42'
      subject.external_hostname = 'test42.example.com'
      subject.external_alt_names = ['test23.example.com', 'production.example.com']

      expect(subject).to receive(:external_address_resolution).and_return resolution
      expect(resolution).to receive(:update_attributes).with(name: 'test42.example.com', alt_names: ["test23.example.com", "production.example.com"])
      subject.apply_address_resolution{true}
    end

    it 'should do nothing if external address is not set' do
      subject.external_address = nil
      expect(subject).to receive(:external_address_resolution).and_return nil
      subject.instance_variable_set :@external_hostname_changed, true
      subject.apply_address_resolution{true}
      expect(subject.instance_variable_get :@external_hostname_changed).to eq true
    end
  end

  describe '#remove_external_address_resolution' do
    it 'should destroy external_address_resolution' do
      resolution = double
      expect(subject).to receive(:external_address_resolution).and_return resolution
      expect(resolution).to receive(:destroy)
      subject.remove_external_address_resolution
    end

    it 'should do nothing if no external address resolution' do
      expect(subject).to receive(:external_address_resolution).and_return nil
      subject.remove_external_address_resolution
    end

    it 'should be called after destroy' do
      expect(subject).to receive(:remove_external_address_resolution)
      subject.run_callbacks :destroy
    end
  end

  describe '#external_alt_names_string' do
    it 'should concat alt_names with a comma' do
      allow(subject).to receive(:external_alt_names).and_return ['alt.example.com', 'www.alt.example.com']

      expect(subject.external_alt_names_string).to eq "alt.example.com,www.alt.example.com"
    end
  end

  describe '#external_alt_names_string=' do
    it 'should allow to set alt_names with comma separated string' do
      subject.external_alt_names_string = "alt.example.com,www.alt.example.com"

      expect(subject.external_alt_names).to eq ['alt.example.com', 'www.alt.example.com']
    end

    it 'should allow spaces in comma separated string' do
      subject.external_alt_names_string = "alt.example.com, www.alt.example.com"

      expect(subject.external_alt_names).to eq ['alt.example.com', 'www.alt.example.com']
    end
  end

  describe '#copy_to_host' do
    let(:target_host) {Factory.build :host}

    it 'should return unpersisted copy of current guest on target host' do
      new_guest = subject.copy_to_host target_host

      expect(target_host.guests.first).to eq new_guest
      expect(new_guest).to_not be_persisted
    end

    it 'should copy over guest external_alt_names' do
      subject.external_alt_names = [double]
      new_guest = subject.copy_to_host target_host
      expect(new_guest.external_alt_names).to eq subject.external_alt_names
    end

    it 'should copy over guest lxd_autostart_priority' do
      subject.lxd_autostart_priority = rand(0..50)
      new_guest = subject.copy_to_host target_host
      expect(new_guest.lxd_autostart_priority).to eq subject.lxd_autostart_priority
    end

    it 'should copy over guest lxd_autostart_delay' do
      subject.lxd_autostart_delay = rand(0..300)
      new_guest = subject.copy_to_host target_host
      expect(new_guest.lxd_autostart_delay).to eq subject.lxd_autostart_delay
    end

    it 'should copy over guest root_fs_size' do
      subject.root_fs_size = rand(65536...1048576) * 1024
      new_guest = subject.copy_to_host target_host
      expect(new_guest.root_fs_size).to eq subject.root_fs_size
    end

    it 'should copy over guest memory_size' do
      subject.memory_size = rand(2..16) * 1024 * 1024
      new_guest = subject.copy_to_host target_host
      expect(new_guest.memory_size).to eq subject.memory_size
    end

    it 'should copy over guest cpu_count' do
      subject.cpu_count = rand(1..8)
      new_guest = subject.copy_to_host target_host
      expect(new_guest.cpu_count).to eq subject.cpu_count
    end

    it 'should copy over guest name' do
      subject.name = Faker::Internet.domain_word
      new_guest = subject.copy_to_host target_host
      expect(new_guest.name).to eq subject.name
    end

    it 'should allow to set new name' do
      subject.name = Faker::Internet.domain_word
      new_name = Faker::Internet.domain_word
      new_guest = subject.copy_to_host target_host, name: new_name
      expect(new_guest.name).to eq new_name
    end

    it 'should assign new private address' do
      subject.private_address = Faker::Internet.private_ip_v4_address
      new_address = Faker::Internet.private_ip_v4_address
      expect(target_host).to receive(:dhcp_private_address).and_return new_address
      new_guest = subject.copy_to_host target_host
      expect(new_guest.private_address).to eq new_address
    end

    it 'should assign new external address if given on subject' do
      subject.external_address = Faker::Internet.ip_v4_address
      new_address = Faker::Internet.ip_v4_address
      expect(target_host).to receive(:dhcp_external_address).and_return new_address
      new_guest = subject.copy_to_host target_host
      expect(new_guest.external_address).to eq new_address
    end

    it 'should assign no external address if not given on subject' do
      subject.external_address = nil
      expect(target_host).not_to receive(:dhcp_external_address)
      new_guest = subject.copy_to_host target_host
      expect(new_guest.external_address).to eq subject.external_address
    end

    it 'should copy over guest external_hostname' do
      subject.external_alt_names = [double]
      new_guest = subject.copy_to_host target_host
      expect(new_guest.external_hostname).to eq subject.external_hostname
    end

    context 'lxd_custom_volumes' do
      it 'should copy values of lxd custom volume' do
        subject.lxd_custom_volumes = [Factory.build(:lxd_custom_volume)]
        new_guest = subject.copy_to_host target_host

        old_volume_data = subject.lxd_custom_volumes.first.as_document
        new_volume_data = new_guest.lxd_custom_volumes.first.as_document

        expect(new_volume_data.delete('_id')).not_to equal old_volume_data.delete('_id')
        expect(new_volume_data).to eq old_volume_data
      end
    end

    context 'services' do
      pending
    end
  end

  describe 'uuid' do
    it 'creates a secure random UUID' do
      expect(SecureRandom).to receive(:uuid).and_return('SECURE_UUID')
      expect(subject.uuid).to eq 'SECURE_UUID'
    end
  end

  describe 'random_2_digit_hex' do
    it 'create a byte long hex number' do
      expect(SecureRandom).to receive(:random_number).with(256).and_return 42
      expect(subject.random_2_digit_hex).to eq '2a'
    end
  end

  describe 'to_param' do
    it 'should have name as param' do
      subject.name = 'blafasel'
      expect(subject.to_param).to eq 'blafasel'
    end
  end

  describe 'item_issue_chain' do
    it 'should return chained items to guest for ItemIssue' do
      subject.host = host
      expect(subject.item_issue_chain).to eq [host, subject]
    end
  end

  describe 'exec' do
    it 'should pass to host exec called with lxd exec' do
      subject.host = host
      allow(subject).to receive(:current_lxd_container).and_return double(name: 'some_guest-202004011337342')
      expect(host).to receive(:exec).with('/usr/bin/lxc exec some_guest-202004011337342 -- command').and_return [true, 'success']
      expect(subject.exec 'command').to eq [true, 'success']
    end
  end

  describe 'exec!' do
    it 'should pass thru to host exec!' do
      subject.host = host
      allow(subject).to receive(:current_lxd_container).and_return double(name: 'some_guest-202004011337342')
      expect(host).to receive(:exec!).with('/usr/bin/lxc exec some_guest-202004011337342 -- command', 'error message').and_return 'success'
      expect(subject.exec! 'command', 'error message').to eq 'success'
    end
  end

  describe 'host_root_path' do
    it 'should return path to container rootfs on host' do
      allow(subject).to receive(:current_lxd_container).and_return double(name: 'some_guest-202004011337342')

      expect(subject.host_root_path).to eq "/var/lib/lxd/containers/some_guest-202004011337342/rootfs/"
    end
  end

  describe 'certificates' do
    it 'should get certificates used in guest and services' do
      guest_certificates = [BSON::ObjectId.new, BSON::ObjectId.new]
      service_certificate = BSON::ObjectId.new
      allow(subject.guest_certificates).to receive(:pluck).with(:certificate_id).and_return guest_certificates

      service1 = double CloudModel::Services::Ssh
      service2 = double CloudModel::Services::Nginx, ssl_cert_id: service_certificate
      allow(subject).to receive(:services).and_return [service1, service2]

      expect(CloudModel::Certificate).to receive(:where).with(:id.in => guest_certificates + [service_certificate]).and_return 'CERTS'

      expect(subject.certificates).to eq 'CERTS'
    end
  end

  describe 'has_certificates?' do
    it 'should be true if guest has certificates' do
      allow(subject).to receive(:certificates).and_return [double]

      expect(subject.has_certificates?).to eq true
    end

    it 'should be false if guest has certificates' do
      allow(subject).to receive(:certificates).and_return []

      expect(subject.has_certificates?).to eq false
    end
  end

  describe 'has_service_type?' do
    before do
      allow(subject).to receive(:services).and_return [
        double(_type: "CloudModel::Services::Mongodb"),
        double(_type: "CloudModel::Services::Nginx"),
      ]
    end

    it 'should return true if services include given type' do
      expect(subject.has_service_type? "CloudModel::Services::Mongodb").to eq true
    end

    it 'should return true if services include given type as Class' do
      expect(subject.has_service_type? CloudModel::Services::Mongodb).to eq true
    end

    it 'should return false if services not include given type' do
      expect(subject.has_service_type? "CloudModel::Services::Solr").to eq false
    end
  end

  describe 'components_needed' do
    it 'should collect all needed components from services' do
      allow(subject).to receive(:services).and_return [
        double(components_needed: [:ruby, :nginx]),
        double(components_needed: [:ruby, :mongodb]),
      ]
      expect(subject.components_needed).to eq [:ruby, :nginx, :mongodb]
    end

    it 'should resolve component dependencies' do
      allow(subject).to receive(:services).and_return [
        double(components_needed: [:solr]),
      ]
      expect(subject.components_needed).to eq [:'java@8', :solr]
    end
  end

  describe 'template_type' do
    it 'should find or create GuestTemplateType for needed components' do
      template_type = double CloudModel::GuestTemplateType
      allow(subject).to receive(:components_needed).and_return [:nginx, :ruby]
      allow(subject).to receive(:os_version).and_return 'basic-2.0'
      expect(CloudModel::GuestTemplateType).to receive(:find_or_create_by).with(components: [:nginx, :ruby], os_version: 'basic-2.0').and_return template_type
      expect(subject.template_type).to eq template_type
    end
  end

  describe 'template' do
    it 'should get last usable template for guest' do
      template_type = double CloudModel::GuestTemplateType
      template = double CloudModel::GuestTemplate
      host = double CloudModel::Host

      allow(subject).to receive(:template_type).and_return template_type
      allow(subject).to receive(:host).and_return host
      allow(template_type).to receive(:last_useable).with(host).and_return template

      expect(subject.template).to eq template
    end
  end

  describe 'worker' do
    it 'should return worker for guest' do
      worker = double CloudModel::Workers::GuestWorker
      expect(CloudModel::Workers::GuestWorker).to receive(:new).with(subject).and_return worker

      expect(subject.worker).to eq worker
    end
  end

  describe '#deploy_state_id_for' do
    CloudModel::Guest.enum_fields[:deploy_state][:values].each do |k,v|
      it "should map #{v} to id #{k}" do
        expect(CloudModel::Guest.deploy_state_id_for v).to eq k
      end
    end
  end

  describe '#deployable_deploy_states' do
    it 'should list deployable deploy_states' do
      expect(subject.class.deployable_deploy_states).to eq [:finished, :failed, :not_started]
    end
  end

  describe '#deployable_deploy_state_ids' do
    it 'should list deployable deploy_state_ids' do
      expect(subject.class.deployable_deploy_state_ids).to eq [240, 241, 255]
    end
  end

  describe 'deployable?' do
    it 'should be true if state is :finished' do
      subject.deploy_state = :finished
      expect(subject).to be_deployable
    end

    it 'should be true if state is :failed' do
      subject.deploy_state = :failed
      expect(subject).to be_deployable
    end

    it 'should be true if state is :not_started' do
      subject.deploy_state = :not_started
      expect(subject).to be_deployable
    end

    it 'should be false if state is :pending' do
      subject.deploy_state = :pending
      expect(subject).not_to be_deployable
    end

    it 'should be false if state is :running' do
      subject.deploy_state = :running
      expect(subject).not_to be_deployable
    end
  end

  describe '#deployable' do
    it 'should return all deployable Guests' do
      scoped = double
      deployable_guests = double
      allow(CloudModel::Guest).to receive(:scoped).and_return scoped
      allow(CloudModel::Guest).to receive(:deployable_deploy_state_ids).and_return [240, 241, 255]
      expect(scoped).to receive(:where).with(:deploy_state_id.in => [240, 241, 255]).and_return deployable_guests
      expect(CloudModel::Guest.deployable).to eq deployable_guests
    end
  end

  describe 'deploy' do
    it 'should enqueue job to deploy host with host´s and guest´s id' do
      subject.host = host
      job = double "ActiveJob"
      expect(CloudModel::GuestJobs::DeployJob).to receive(:perform_later).with(subject.id.to_s).and_return job

      expect(subject.deploy).to eq job
    end

    it 'should add an error if job enqueue excepts' do
      subject.host = host
      expect(CloudModel::GuestJobs::DeployJob).to receive(:perform_later).with(subject.id.to_s).and_raise 'ERROR 42'

      expect(subject.deploy).to eq false

      expect(subject.deploy_state).to eq :failed
      expect(subject.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end

    it 'should not enqueue deplayed job if not deployable' do
      subject.host = host
      job = double "ActiveJob"
      expect(CloudModel::GuestJobs::DeployJob).not_to receive(:perform_later)
      allow(subject).to receive(:deployable?).and_return false

      expect(subject.deploy).to eq false
    end
  end

  describe 'deploy!' do
    it 'should call worker to deploy Guest' do
      worker = double CloudModel::Workers::GuestWorker, deploy: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:deployable?).and_return true

      expect(subject.deploy!).to eq true
    end

    it 'should return false and not run worker if not deployable' do
      expect(subject).not_to receive(:worker)
      allow(subject).to receive(:deployable?).and_return false

      expect(subject.deploy!).to eq false
      expect(subject.deploy_state).to eq :not_started
    end

    it 'should allow to force deploy if not deployable' do
      worker = double CloudModel::Workers::GuestWorker, deploy: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:deployable?).and_return false

      expect(subject.deploy! force:true).to eq true
    end
  end

  describe 'redeploy' do
    it 'should enquere job host redeploy with host´s and guest´s id' do
      subject.host = host
      job = double "ActiveJob"
      expect(CloudModel::GuestJobs::RedeployJob).to receive(:perform_later).with(subject.id.to_s).and_return job

      expect(subject.redeploy).to eq job
    end

    it 'should add an error if enqueue excepts' do
      subject.host = host
      expect(CloudModel::GuestJobs::RedeployJob).to receive(:perform_later).with(subject.id.to_s).and_raise 'ERROR 42'

      expect(subject.redeploy).to eq false
      expect(subject.deploy_state).to eq :failed
      expect(subject.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end

    it 'should not enqueue job if not deployable' do
      subject.host = host
      expect(CloudModel::GuestJobs::RedeployJob).not_to receive(:perform_later)
      allow(subject).to receive(:deployable?).and_return false

      expect(subject.redeploy).to eq false
    end
  end

  describe 'redeploy!' do
    it 'should call worker to deploy Guest' do
      worker = double CloudModel::Workers::GuestWorker, redeploy: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:deployable?).and_return true

      expect(subject.redeploy!).to eq true
    end

    it 'should return false and not run worker if not deployable' do
      expect(subject).not_to receive(:worker)
      allow(subject).to receive(:deployable?).and_return false

      expect(subject.redeploy!).to eq false
      expect(subject.deploy_state).to eq :not_started
    end

    it 'should allow to force deploy if not deployable' do
      worker = double CloudModel::Workers::GuestWorker, redeploy: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:deployable?).and_return false

      expect(subject.redeploy! force:true).to eq true
    end
  end

  describe '#redeploy' do
    before do
      allow_any_instance_of(CloudModel::Host).to receive(:exec).and_return [true, '']
    end

    let!(:guest1) { Factory :guest, name: 'g1', private_address: '10.42.0.23' }
    let!(:guest2) { Factory :guest, name: 'g2', private_address: '10.42.0.25' }
    let!(:guest3) { Factory :guest, name: 'g3', private_address: '10.42.0.4' }

    it 'should enqueue job cloudmodel:host:deploy_many with list of guest ids' do
      job = double "ActiveJob"
      expect(CloudModel::GuestJobs::RedeployManyJob).to receive(:perform_later).with([guest1.id, guest3.id]).and_return job

      expect(CloudModel::Guest.redeploy ['2600', guest1.id.to_s, guest3.id]).to eq job

      expect(guest1.reload.deploy_state).to eq :pending
      expect(guest2.reload.deploy_state).to eq :not_started
      expect(guest3.reload.deploy_state).to eq :pending
    end

    it 'should add an error if enqueue excepts' do
      expect(CloudModel::GuestJobs::RedeployManyJob).to receive(:perform_later).with([guest1.id, guest3.id]).and_raise 'ERROR 42'

      expect(CloudModel::Guest.redeploy ['2600', guest1.id.to_s, guest3.id]).to eq false

      expect(guest1.reload.deploy_state).to eq :failed
      expect(guest1.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
      expect(guest2.deploy_state).to eq :not_started
      expect(guest2.deploy_last_issue).to be_nil
      expect(guest3.reload.deploy_state).to eq :failed
      expect(guest3.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end

    it 'should not call enqueue job if not deployable' do
      expect(CloudModel::GuestJobs::RedeployManyJob).not_to receive(:perform_later)

      expect(CloudModel::Guest.redeploy ['2600']).to eq false
    end
  end

  describe 'check_mk_agent' do
    pending
  end

  describe 'system_info' do
    pending
  end

  describe 'mem_usage' do
    it 'should return percentage used' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
          'mem' => {
            'mem_total' => '65536',
            'mem_available' => '38911'
          }
        }
      })
      expect(subject.mem_usage).to eq 100.0-100.0*38911/65536
    end

    it 'should return nil if total is 0' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
          'mem' => {
            'mem_total' => '0',
            'mem_available' => '0'
          }
        }
      })
      expect(subject.mem_usage).to eq nil
    end

    it 'should return nil if total not given' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
          'mem' => {
            'mem_available' => '38911'
          }
        }
      })
      expect(subject.mem_usage).to eq nil
    end

    it 'should return 100% if available not given' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
          'mem' => {
            'mem_total' => '65536'
          }
        }
      })
      expect(subject.mem_usage).to eq 100.0
    end

    it 'should return nil if mem not given' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
        }
      })
      expect(subject.mem_usage).to eq nil
    end

    it 'should return nil if system not given' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({})
      expect(subject.mem_usage).to eq nil
    end
  end

  describe 'swap_usage' do
    it 'should return percentage used' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
          'mem' => {
            'swap_total' => '65536',
            'swap_free' => '38911'
          }
        }
      })
      expect(subject.swap_usage).to eq 100.0-100.0*38911/65536
    end

    it 'should return nil if total is 0' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
          'mem' => {
            'swap_total' => '0',
            'swap_free' => '0'
          }
        }
      })
      expect(subject.swap_usage).to eq nil
    end

    it 'should return nil if total not given' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
          'mem' => {
            'swap_free' => '38911'
          }
        }
      })
      expect(subject.swap_usage).to eq nil
    end

    it 'should return 100% if free not given' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
          'mem' => {
            'swap_total' => '65536'
          }
        }
      })
      expect(subject.swap_usage).to eq 100.0
    end

    it 'should return nil if mem not given' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({
        'system' => {
        }
      })
      expect(subject.swap_usage).to eq nil
    end

    it 'should return nil if system not given' do
      allow(subject).to receive(:monitoring_last_check_result).and_return({})
      expect(subject.swap_usage).to eq nil
    end
  end

  describe 'cpu_usage' do
    pending
  end

  describe 'apply_memory_size' do
    let(:container) { double CloudModel::LxdContainer }

    it 'should set memory limit on given container' do
      expect(subject).not_to receive(:current_lxd_container)
      subject.memory_size = '128K'
      expect(container).to receive(:set_config).with("limits.memory", 131072).and_return [true, '']

      expect(subject.apply_memory_size container).to eq [true, '']
    end

    it 'should set memory limit on current container by default' do
      allow(subject).to receive(:current_lxd_container).and_return container
      subject.memory_size = '64K'
      expect(container).to receive(:set_config).with("limits.memory", 65536).and_return [true, '']

      expect(subject.apply_memory_size).to eq [true, '']
    end

    it 'should return nil if no current container found' do
      allow(subject).to receive(:current_lxd_container).and_return nil
      expect(subject.apply_memory_size).to eq nil
    end
  end

  describe 'apply_cpu_count' do
    let(:container) { double CloudModel::LxdContainer }

    it 'should set memory limit on given container' do
      expect(subject).not_to receive(:current_lxd_container)
      subject.cpu_count = 4
      expect(container).to receive(:set_config).with("limits.cpu", 4).and_return [true, '']

      expect(subject.apply_cpu_count container).to eq [true, '']
    end

    it 'should set memory limit on current container by default' do
      allow(subject).to receive(:current_lxd_container).and_return container
      subject.cpu_count = 1
      expect(container).to receive(:set_config).with("limits.cpu", 1).and_return [true, '']

      expect(subject.apply_cpu_count).to eq [true, '']
    end

    it 'should return nil if no current container found' do
      allow(subject).to receive(:current_lxd_container).and_return nil
      expect(subject.apply_cpu_count).to eq nil
    end
  end

  describe 'apply_lxd_autostart' do
    let(:container) { double CloudModel::LxdContainer }

    it 'should set memory limit on given container' do
      expect(subject).not_to receive(:current_lxd_container)
      subject.lxd_autostart_priority = 42
      subject.lxd_autostart_delay = 0
      expect(container).to receive(:set_config).with("boot.autostart.priority", 42).and_return [true, '']
      expect(container).to receive(:set_config).with("boot.autostart.delay", 0).and_return [true, '']

      expect(subject.apply_lxd_autostart container).to eq [true, '']
    end

    it 'should set memory limit on current container by default' do
      allow(subject).to receive(:current_lxd_container).and_return container
      subject.lxd_autostart_priority = 23
      subject.lxd_autostart_delay = 13
      expect(container).to receive(:set_config).with("boot.autostart.priority", 23).and_return [true, '']
      expect(container).to receive(:set_config).with("boot.autostart.delay", 13).and_return [true, '']

      expect(subject.apply_lxd_autostart).to eq [true, '']
    end

    it 'should return nil if no current container found' do
      allow(subject).to receive(:current_lxd_container).and_return nil
      expect(subject.apply_lxd_autostart).to eq nil
    end
  end

  describe 'configure_lxd_container' do
    let(:container) { double CloudModel::LxdContainer }

    it 'should call apply cpu count, memory limit, and lxd autostart' do
      expect(subject).to receive(:apply_cpu_count).with(container)
      expect(subject).to receive(:apply_memory_size).with(container)
      expect(subject).to receive(:apply_lxd_autostart).with(container)
      expect(subject.configure_lxd_container container).to eq true
    end
  end

  describe 'configure_current_lxd_container' do
    let(:container) { double CloudModel::LxdContainer }

    it 'should call apply cpu count and memory limit' do
      allow(subject).to receive(:current_lxd_container).and_return container
      expect(subject).to receive(:configure_lxd_container).with(container).and_return true
      expect(subject.configure_current_lxd_container).to eq true
    end
  end

  describe 'apply_current_lxd_container_config' do
    # def apply_current_lxd_container_config
    #   memory_changed = memory_size_changed?
    #   cpu_changed    = cpu_count_changed?
    #   autostart_prio_changed    = lxd_autostart_priority_changed?
    #   autostart_delay_changed    = lxd_autostart_delay_changed?
    #
    #   res = yield
    #
    #   if res and current_lxd_container
    #     if memory_changed
    #       current_lxd_container.set_config 'limits.memory', memory_size
    #     end
    #     if cpu_changed
    #       current_lxd_container.set_config 'limits.cpu', cpu_count
    #     end
    #     if autostart_prio_changed
    #       current_lxd_container.set_config 'boot.autostart.priority', lxd_autostart_priority
    #     end
    #     if autostart_delay_changed
    #       current_lxd_container.set_config 'boot.autostart.delay', lxd_autostart_delay
    #     end
    #   end
    #   res
    # end

    let(:container) { double CloudModel::LxdContainer }

    before do
      subject.move_changes # Mark model to have no changes/persisted
    end

    it 'should not call any container set config if nothing changed' do
      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).not_to receive(:set_config)

      expect(subject.apply_current_lxd_container_config{true}).to eq true
    end

    it 'should call container set config if memory size changed' do
      subject.memory_size = '64K'
      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).to receive(:set_config).with("limits.memory", 65536)
      expect(container).not_to receive(:set_config)

      expect(subject.apply_current_lxd_container_config{true}).to eq true
    end

    it 'should call container set config if cpu count changed' do
      subject.cpu_count = 8
      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).to receive(:set_config).with("limits.cpu", 8)
      expect(container).not_to receive(:set_config)

      expect(subject.apply_current_lxd_container_config{true}).to eq true
    end

    it 'should call container set config if autostart priority changed' do
      subject.lxd_autostart_priority = 42
      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).to receive(:set_config).with("boot.autostart.priority", 42)
      expect(container).not_to receive(:set_config)

      expect(subject.apply_current_lxd_container_config{true}).to eq true
    end

    it 'should call container set config if autostart delay changed' do
      subject.lxd_autostart_delay = 3
      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).to receive(:set_config).with("boot.autostart.delay", 3)
      expect(container).not_to receive(:set_config)

      expect(subject.apply_current_lxd_container_config{true}).to eq true
    end

    it 'should call multiple container set config multiple things changed' do
      subject.memory_size = '64K'
      subject.cpu_count = 8
      subject.lxd_autostart_priority = 42
      subject.lxd_autostart_delay = 3

      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).to receive(:set_config).with("limits.memory", 65536)
      expect(container).to receive(:set_config).with("limits.cpu", 8)
      expect(container).to receive(:set_config).with("boot.autostart.priority", 42)
      expect(container).to receive(:set_config).with("boot.autostart.delay", 3)

      expect(subject.apply_current_lxd_container_config{true}).to eq true
    end

    it 'should not call any container set config if save failed' do
      subject.memory_size = '64K'
      subject.cpu_count = 8
      subject.lxd_autostart_priority = 42
      subject.lxd_autostart_delay = 3

      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).not_to receive(:set_config)

      expect(subject.apply_current_lxd_container_config{false}).to eq false
    end

    it 'should call it on saving the guest' do
      expect(subject).to receive(:apply_current_lxd_container_config)
      subject.run_callbacks(:save)
    end
  end

  describe 'live_lxc_info' do
    it 'should delegate to current container' do
      lxc_info = double
      allow(subject).to receive(:current_lxd_container).and_return double
      expect(subject.current_lxd_container).to receive(:live_lxc_info).and_return lxc_info
      expect(subject.live_lxc_info).to eq lxc_info
    end

    it 'should return nil if no current container' do
      allow(subject).to receive(:current_lxd_container).and_return nil
      expect(subject.live_lxc_info).to eq nil
    end
  end

  describe 'lxc_info' do
    it 'should delegate to current container' do
      lxc_info = double
      allow(subject).to receive(:current_lxd_container).and_return double
      expect(subject.current_lxd_container).to receive(:lxc_info).and_return lxc_info
      expect(subject.lxc_info).to eq lxc_info
    end

    it 'should return nil if no current container' do
      allow(subject).to receive(:current_lxd_container).and_return nil
      expect(subject.lxc_info).to eq nil
    end
  end

  describe 'start' do
    it 'should call start on current containers of guest by default' do
      container = double CloudModel::LxdContainer
      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).to receive(:start).and_return [true, '']

      expect(subject.start).to eq [true, '']
    end

    it 'should call start on given container and set it to current container' do
      container1 = double CloudModel::LxdContainer, running?: true
      container2 = double CloudModel::LxdContainer, running?: false, id: '42', is_a?: CloudModel::LxdContainer
      allow(subject).to receive(:lxd_containers).and_return [container1, container2]
      allow(subject).to receive(:current_lxd_container).and_return container1

      expect(container1).not_to receive(:start)
      expect(container2).to receive(:start).and_return [true, '']
      expect(subject).to receive(:update_attributes).with(current_lxd_container_id: '42') do
        allow(subject).to receive(:current_lxd_container).and_return container2
      end

      expect(subject.start container2).to eq [true, '']
    end

    it 'should call start on given container and set it to current container' do
      container1 = double CloudModel::LxdContainer, running?: true
      container2 = double CloudModel::LxdContainer, running?: false
      allow(subject).to receive(:lxd_containers).and_return [container1, container2]
      allow(subject).to receive(:current_lxd_container).and_return container1

      expect(container1).not_to receive(:start)
      expect(container2).to receive(:start).and_return [true, '']
      expect(subject).to receive(:update_attributes).with(current_lxd_container_id: '42') do
        allow(subject).to receive(:current_lxd_container).and_return container2
      end

      expect(subject.start "42").to eq [true, '']
    end

    it 'should return false if starting container fails fatally' do
      container = double CloudModel::LxdContainer, running?: true
      allow(subject).to receive(:current_lxd_container).and_return container
      expect(container).to receive(:start).and_raise('ooops')

      expect(subject.start).to eq [false, 'ooops']
    end
  end

  describe 'stop' do
    it 'should call stop on all running containers of guest with given options' do
      options = double
      container1 = double CloudModel::LxdContainer, running?: true
      container2 = double CloudModel::LxdContainer, running?: false
      container3 = double CloudModel::LxdContainer, running?: true # Even if that should not happen, let's assume we have to containers running by some mistake
      allow(subject).to receive(:lxd_containers).and_return [container1, container2, container3]

      expect(container1).to receive(:stop).with(options).and_return [true, '']
      expect(container2).not_to receive(:stop)
      expect(container3).to receive(:stop).with(options).and_return [false, 'Container not even running for real']


      expect(subject.stop options).to eq true
    end

    it 'should return false if stopping container fails fatally' do
      options = double
      container = double CloudModel::LxdContainer, running?: true
      allow(subject).to receive(:lxd_containers).and_return [container]

      expect(container).to receive(:stop).with(options).and_raise('ooops')

      expect(subject.stop options).to eq false
    end
  end

  describe 'fix_lxd_custom_volumes' do
    pending
  end

  describe 'backup' do
    pending
  end

  describe 'restore' do
    pending
  end

  describe 'generate_mac_address' do
    pending
  end

  describe 'set_dhcp_private_address' do
    pending
  end

  describe 'set_mac_address' do
    pending
  end
end