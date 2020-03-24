# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Guest do
  it { expect(subject).to be_timestamped_document }  

  it { expect(subject).to belong_to(:host).of_type CloudModel::Host }
  it { expect(subject).to embed_many(:services).of_type CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:name).of_type String }
  
  it { expect(subject).to have_field(:private_address).of_type String }
  it { expect(subject).to have_field(:external_address).of_type String }

  it { expect(subject).to have_field(:memory_size).of_type(Integer).with_default_value_of 2*1024*1024*1024 }
  it { expect(subject).to have_field(:cpu_count).of_type(Integer).with_default_value_of 2 }

  it { expect(subject).to have_enum(:deploy_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0xf0 => :finished,
    0xf1 => :failed,
    0xff => :not_started
  ).with_default_value_of(:not_started) }
  
  it{ expect(subject).to have_field(:deploy_last_issue).of_type String }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name).scoped_to(:host) }
  it { expect(subject).to validate_format_of(:name).to_allow("host-name-01").not_to_allow("Test Host") }
  
  it { expect(subject).to validate_presence_of(:host) }
  it { expect(subject).to validate_presence_of(:root_volume) }
  it { expect(subject).to validate_presence_of(:private_address) }
  
  context 'memory_size=' do
    it 'should parse input as size string' do
      expect(subject).to receive(:accept_size_string_parser).with('Size String').and_return(42)
      subject.memory_size = 'Size String'
      
      expect(subject.memory_size).to eq 42
    end
  end
  
  context 'base_path' do
    it 'should have base path based on name' do
      subject.name = 'test-host'
      expect(subject.base_path).to eq '/vm/test-host'
    end
  end
  
  context 'deploy_volume' do
    it 'should return root_volume if not set' do
      expect(subject.deploy_volume).to eq subject.root_volume
    end
    
    it 'should allow overwriting the deploy volume' do
      volume = mock_model CloudModel::LogicalVolume
      subject.deploy_volume = volume
      expect(subject.deploy_volume).to eq volume
    end
  end
  
  context 'deploy_path' do
    it 'should return base_path if not set' do
      subject.stub(:base_path) { 'BASE_PATH' }
      expect(subject.deploy_path).to eq 'BASE_PATH'
    end
    
    it 'should allow overwriting the deploy volume' do
      subject.deploy_volume = 'DEPLOY_PATH'
      expect(subject.deploy_volume).to eq 'DEPLOY_PATH'
    end  
  end
  
  context 'config_root_path' do
    it 'should have config_root_path relative to base_path' do
      subject.stub(:base_path) { 'BASE_PATH' }
      expect(subject.config_root_path).to eq 'BASE_PATH/etc'
    end
  end
  
  context 'available_private_address_collection' do
    it 'should return host´s available_private_address_collection and add it´s own private address' do
      subject.host = Factory.build :host
      subject.host.should_receive(:available_private_address_collection).and_return(['10.42.42.4', '10.42.42.6'])
      subject.private_address = '10.42.42.12'
      expect(subject.available_private_address_collection).to eq [
        '10.42.42.12',
        '10.42.42.4',
        '10.42.42.6'
      ]
    end
  end
  
  context 'available_external_address_collection' do
    it 'should return host´s available_external_address_collection and add it´s own external address' do
      subject.host = Factory.build :host
      subject.host.should_receive(:available_external_address_collection).and_return(['192.168.42.4', '192.168.42.6'])
      subject.external_address = '192.168.42.12'
      expect(subject.available_external_address_collection).to eq [
        '192.168.42.12',
        '192.168.42.4',
        '192.168.42.6'
      ]
    end
  end
  
  context 'external_hostname' do
    it 'should lookup the hostname for the external ip' do
      Resolv.stub(:getname).with('127.0.0.1').and_return('localhost')
      subject.external_address = '127.0.0.1'
      expect(subject.external_hostname).to eq 'localhost'
    end
    
    it 'should return the raw ip if lookup fails' do
      Resolv.stub(:getname).with('127.0.0.1').and_raise('DNS not available')
      subject.external_address = '127.0.0.1'
      expect(subject.external_hostname).to eq '127.0.0.1'
    end
  end
  
  context 'uuid' do
    it 'creates a secure random UUID' do
      expect(SecureRandom).to receive(:uuid).and_return('SECURE_UUID')
      expect(subject.uuid).to eq 'SECURE_UUID'
    end
  end
  
  context 'random_2_digit_hex' do
    it 'create a byte long hex number' do
      expect(SecureRandom).to receive(:random_number).with(256).and_return 42
      expect(subject.random_2_digit_hex).to eq '2a'
    end
  end
  
  context 'mac_address' do
    it 'should create a valid virtual mac address' do
      expect(subject.mac_address).to match /^52:54:00:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]:[0-9a-f][0-9a-f]$/
    end
  end
  
  context 'to_param' do
    it 'should have name as param' do
      subject.name = 'blafasel'
      expect(subject.to_param).to eq 'blafasel'
    end
  end
  
  context 'exec' do
    it 'should pass thru to host exec' do
      host = CloudModel::Host.new
      subject.host = host
      host.should_receive(:exec).with('command').and_return [true, 'success']
      expect(subject.exec 'command').to eq [true, 'success']
    end
  end
 
  context 'deployable?' do
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
  
  context 'deploy' do
    it 'should call rake cloudmodel:host:deploy with host´s and guest´s id' do
      subject.host = CloudModel::Host.new
      CloudModel.should_receive(:call_rake).with('cloudmodel:guest:deploy', host_id: subject.host.id, guest_id: subject.id)
      subject.deploy
    end 
    
    it 'should add an error if call_rake excepts' do
      subject.host = CloudModel::Host.new
      CloudModel.stub(:call_rake).with('cloudmodel:guest:deploy', host_id: subject.host.id, guest_id: subject.id).and_raise 'ERROR 42'
      subject.deploy
      expect(subject.deploy_state).to eq :failed
      expect(subject.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
    
    it 'should not call rake if not deployable' do
      subject.host = CloudModel::Host.new
      CloudModel.should_not_receive(:call_rake).with('cloudmodel:guest:deploy', host_id: subject.host.id, guest_id: subject.id)
      subject.stub(:deployable?).and_return false
      expect(subject.deploy).to be_false
    end
  end  
  
  context 'redeploy' do
    it 'should call rake cloudmodel:host:deploy with host´s and guest´s id' do
      subject.host = CloudModel::Host.new
      CloudModel.should_receive(:call_rake).with('cloudmodel:guest:redeploy', host_id: subject.host.id, guest_id: subject.id)
      subject.redeploy
    end 
    
    it 'should add an error if call_rake excepts' do
      subject.host = CloudModel::Host.new
      CloudModel.stub(:call_rake).with('cloudmodel:guest:redeploy', host_id: subject.host.id, guest_id: subject.id).and_raise 'ERROR 42'
      subject.redeploy
      expect(subject.deploy_state).to eq :failed
      expect(subject.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
    
    it 'should not call rake if not deployable' do
      subject.host = CloudModel::Host.new
      CloudModel.should_not_receive(:call_rake).with('cloudmodel:guest:redeploy', host_id: subject.host.id, guest_id: subject.id)
      subject.stub(:deployable?).and_return false
      expect(subject.redeploy).to be_false
    end
  end
  
  context '#redeploy' do
    before do
      CloudModel::Host.any_instance.stub(:exec).and_return [true, '']
    end    
    
    let!(:guest1) { Factory :guest, name: 'g1', private_address: '10.42.0.23' }
    let!(:guest2) { Factory :guest, name: 'g2', private_address: '10.42.0.25' }
    let!(:guest3) { Factory :guest, name: 'g3', private_address: '10.42.0.4' }
    
    it 'should call rake cloudmodel:host:deploy_many with list of guest ids' do  
      CloudModel.should_receive(:call_rake).with('cloudmodel:guest:redeploy_many', guest_ids: "#{guest1.id} #{guest3.id}")
      CloudModel::Guest.redeploy ['2600', guest1.id.to_s, guest3.id]

      expect(guest1.reload.deploy_state).to eq :pending
      expect(guest2.reload.deploy_state).to eq :not_started
      expect(guest3.reload.deploy_state).to eq :pending    
    end 
    
    it 'should add an error if call_rake excepts' do
      CloudModel.stub(:call_rake).with('cloudmodel:guest:redeploy_many', guest_ids: [guest1.id, guest3.id] * '').and_raise 'ERROR 42'
      CloudModel::Guest.redeploy ['2600', guest1.id.to_s, guest3.id]
      expect(guest1.reload.deploy_state).to eq :failed
      expect(guest1.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
      expect(guest2.deploy_state).to eq :not_started
      expect(guest2.deploy_last_issue).to be_nil
      expect(guest3.reload.deploy_state).to eq :failed
      expect(guest3.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
    
    it 'should not call rake if not deployable' do
      CloudModel.should_not_receive(:call_rake).with('cloudmodel:guest:redeploy_many', guest_ids: [guest1.id, guest3.id].map(&:to_s))
      expect(CloudModel::Guest.redeploy ['2600']).to be_false
    end
  end
  
  context 'state' do
    it 'should get the current state as id from virsh' do
      subject.should_receive(:virsh).with('domstate').and_return 'state_string'
      expect(subject.state).to eq 42
    end
  end
  
  context 'start' do
    it 'should enables autostart state for domain' do
      subject.stub(:virsh).and_return true
      subject.should_receive(:virsh).with('autostart').and_return true
      subject.start
    end
    
    it 'should start domain' do
      subject.stub(:virsh).and_return true
      subject.should_receive(:virsh).with('start').and_return true
      subject.start
    end
    
    it 'should return true if no error occures' do
      subject.stub(:virsh).and_return true
      expect(subject.start).to eq true
    end

    it 'should return false if error occures' do
      subject.stub(:virsh).and_raise 'Oops'
      expect(subject.start).to eq false
    end
  end
  
  context 'stop' do
    it 'should disables autostart state for domain' do
      subject.stub(:virsh).and_return true
      subject.should_receive(:virsh).with('autostart', 'disable').and_return true
      subject.stop
    end
    
    it 'should stop domain' do
      subject.stub(:virsh).and_return true
      subject.should_receive(:virsh).with('shutdown').and_return true
      subject.stop
    end
    
    it 'should return true if no error occures' do
      subject.stub(:virsh).and_return true
      expect(subject.stop).to eq true
    end

    it 'should return false if error occures' do
      subject.stub(:virsh).and_raise 'Oops'
      expect(subject.stop).to eq false
    end
  end
  
  context 'define' do
    pending
  end
  
  context 'undefine' do    
    it 'should stop and undefine domain' do
      subject.stub(:virsh).and_return true
      subject.stub(:state).and_return 1
      subject.should_receive(:stop!)
      subject.should_receive(:virsh).with('undefine').and_return true
      subject.undefine
    end
    
    it 'should return true if no error occures' do
      subject.stub(:state).and_return 1
      subject.should_receive(:stop!)
      subject.stub(:virsh).and_return true
      expect(subject.undefine).to eq true
    end

    it 'should return false if error occures' do
      subject.stub(:state).and_return 1
      subject.should_receive(:stop!)
      subject.stub(:virsh).and_raise 'Oops'
      expect(subject.undefine).to eq false
    end
  end
  
  context 'set_root_volume_name' do
    it 'should be called before validation' do
      subject.should_receive(:set_root_volume_name)
      subject.valid?
    end
    
    it 'should set generic root volume name' do
      subject.name = 'my_guest'
      Time.stub(:now).and_return(Time.parse('2014-05-23 23:42:17'))
      subject.send :set_root_volume_name
      expect(subject.root_volume.name).to eq 'my_guest-root-20140523234217'
    end
    
    it 'should not overwrite existing root volume name' do
      subject.name = 'my_guest'
      subject.root_volume.name = 'this-is-a-custom-volume-name'
      subject.send :set_root_volume_name
      expect(subject.root_volume.name).to eq 'this-is-a-custom-volume-name'
    end
  end
  
end