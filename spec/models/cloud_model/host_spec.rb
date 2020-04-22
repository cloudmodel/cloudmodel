# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Host do
   
  it { expect(subject).to have_timestamps }  
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:tinc_public_key).of_type String }
  it { expect(subject).to have_field(:initial_root_pw).of_type String }
  it { expect(subject).to have_field(:cpu_count).of_type(Integer).with_default_value_of -1 }
  it { expect(subject).to have_field(:arch).of_type(String).with_default_value_of 'amd64' }
  it { expect(subject).to have_field(:mac_address_prefix).of_type String }
  
  it { expect(subject).to have_enum(:stage).with_values(
    0x00 => :pending,
    0x10 => :testing,
    0x30 => :staging,
    0x40 => :production,
  ).with_default_value_of(:pending) }
  
  it { expect(subject).to have_enum(:deploy_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0xe0 => :booting,
    0xf0 => :finished,
    0xf1 => :failed,
    0xff => :not_started
  ).with_default_value_of(:not_started) }
  
  it { expect(subject).to have_field(:deploy_last_issue).of_type String }
  
  it { expect(subject).to have_many(:guests).of_type CloudModel::Guest }
  it { expect(subject).to embed_many(:addresses).of_type CloudModel::Address }
  it { expect(subject).to accept_nested_attributes_for(:addresses) }
  it { expect(subject).to embed_one(:primary_address).of_type CloudModel::Address }
  it { expect(subject).to accept_nested_attributes_for(:primary_address) }
  it { expect(subject).to embed_one(:private_network).of_type CloudModel::Address }
  it { expect(subject).to accept_nested_attributes_for(:private_network) }
  
  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name) }
  it { expect(subject).to validate_format_of(:name).to_allow("host-name-01") }
  it { expect(subject).to validate_format_of(:name).not_to_allow("Test Host") }
  it { expect(subject).to validate_presence_of(:primary_address) }
  it { expect(subject).to validate_presence_of(:private_network) }
  it { expect(subject).to validate_presence_of(:mac_address_prefix) }
  it { expect(subject).to validate_uniqueness_of(:mac_address_prefix) }
  
  describe 'addresses=' do
    it 'should accept strings to be added' do
      subject.addresses << CloudModel::Address.new(ip: '10.42.23.11', subnet: 26)
      subject.addresses << '192.168.42.1/28'
      expect(subject.addresses.size).to eq 2
      expect(subject.addresses.map(&:class)).to eq [CloudModel::Address, CloudModel::Address]
      expect(subject.addresses.map(&:to_s)).to eq ['10.42.23.11/26', '192.168.42.1/28']
    end
    
    it 'should accept strings as initial array' do
      subject.addresses << '10.23.0.42/29'
      subject.addresses = [CloudModel::Address.new(ip: '10.42.23.11', subnet: 26), '192.168.42.1/28']
      expect(subject.addresses.size).to eq 2
      expect(subject.addresses.map(&:class)).to eq [CloudModel::Address, CloudModel::Address]
      expect(subject.addresses.map(&:to_s)).to eq ['10.42.23.11/26', '192.168.42.1/28']
    end
    
    it 'should accept hashes to be added' do
      subject.addresses << CloudModel::Address.new(ip: '10.42.23.11', subnet: 26)
      subject.addresses << {ip: '192.168.42.1', subnet: 28}
      expect(subject.addresses.size).to eq 2
      expect(subject.addresses.map(&:class)).to eq [CloudModel::Address, CloudModel::Address]
      expect(subject.addresses.map(&:to_s)).to eq ['10.42.23.11/26', '192.168.42.1/28']
    end
    
    it 'should accept hashes as initial array' do
      subject.addresses << {ip: '10.23.0.42', subnet: 29}
      subject.addresses = [CloudModel::Address.new(ip: '10.42.23.11', subnet: 26), '192.168.42.1/28']
      expect(subject.addresses.size).to eq 2
      expect(subject.addresses.map(&:class)).to eq [CloudModel::Address, CloudModel::Address]
      expect(subject.addresses.map(&:to_s)).to eq ['10.42.23.11/26', '192.168.42.1/28']
    end
  end
  
  describe 'to_param' do
    it 'should return name as param' do
      subject.name = 'some_host'
      expect(subject.to_param).to eq 'some_host'
    end
  end
  
  describe 'primary_address=' do
    context 'should accept string' do
      before do
        subject.primary_address = '192.168.42.1/28'
      end
      
      it 'should convert to CloudModel::Address' do
        expect(subject.primary_address.class).to eq CloudModel::Address
      end
      
      it 'should store ip' do
        expect(subject.primary_address.ip).to eq '192.168.42.1'
      end
      
      it 'should store subnet' do
        expect(subject.primary_address.subnet).to eq 28
      end
    end
    
    context 'should accept hash' do
      before do
        subject.primary_address = {ip: '192.168.42.1' ,subnet: 28}
      end
      
      it 'should convert to CloudModel::Address' do
        expect(subject.primary_address.class).to eq CloudModel::Address
      end
      
      it 'should store ip' do
        expect(subject.primary_address.ip).to eq '192.168.42.1'
      end
      
      it 'should store subnet' do
        expect(subject.primary_address.subnet).to eq 28
      end
    end
    
    context 'should accept hash on mass assign' do
      let(:host) { CloudModel::Host.new primary_address: {ip: '192.168.42.1' ,subnet: 28} }
      
      it 'should convert to CloudModel::Address' do
        expect(host.primary_address.class).to eq CloudModel::Address
      end
      
      it 'should store ip' do
        expect(host.primary_address.ip).to eq '192.168.42.1'
      end
      
      it 'should store subnet' do
        expect(host.primary_address.subnet).to eq 28
      end
    end
    
    context 'should accept string on mass assign' do
      let(:host) { CloudModel::Host.new primary_address: '192.168.42.1/28' }
      
      it 'should convert to CloudModel::Address' do
        expect(host.primary_address.class).to eq CloudModel::Address
      end
      
      it 'should store ip' do
        expect(host.primary_address.ip).to eq '192.168.42.1'
      end
      
      it 'should store subnet' do
        expect(host.primary_address.subnet).to eq 28
      end
    end
  end
  
  describe 'private_network=' do    
    context 'should accept string' do
      before do
        subject.private_network = '10.42.23.14/27'
      end
      
      it 'should convert to CloudModel::Address' do
        expect(subject.private_network.class).to eq CloudModel::Address
      end
      
      it 'should store ip' do
        expect(subject.private_network.ip).to eq '10.42.23.14'
      end
      
      it 'should store subnet' do
        expect(subject.private_network.subnet).to eq 27
      end
    end
    
    context 'should accept hash' do
      before do
        subject.private_network = {ip: '10.42.23.14', subnet: 27}
      end
      
      it 'should convert to CloudModel::Address' do
        expect(subject.private_network.class).to eq CloudModel::Address
      end
      
      it 'should store ip' do
        expect(subject.private_network.ip).to eq '10.42.23.14'
      end
      
      it 'should store subnet' do
        expect(subject.private_network.subnet).to eq 27
      end
    end
    
    context 'should accept hash on mass assign' do
      let(:host) { CloudModel::Host.new private_network: {ip: '192.168.42.1' ,subnet: 28} }
      
      it 'should convert to CloudModel::Address' do
        expect(host.private_network.class).to eq CloudModel::Address
      end
      
      it 'should store ip' do
        expect(host.private_network.ip).to eq '192.168.42.1'
      end
      
      it 'should store subnet' do
        expect(host.private_network.subnet).to eq 28
      end
    end
    
    context 'should accept string on mass assign' do
      let(:host) { CloudModel::Host.new private_network: '192.168.42.1/28' }
      
      it 'should convert to CloudModel::Address' do
        expect(host.private_network.class).to eq CloudModel::Address
      end
      
      it 'should store ip' do
        expect(host.private_network.ip).to eq '192.168.42.1'
      end
      
      it 'should store subnet' do
        expect(host.private_network.subnet).to eq 28
      end
    end
  end
  
  describe 'available_private_address_collection' do
    it 'should get the last available address from block' do
      subject.private_network = '10.42.42.0/29'
      subject.private_network.gateway = '10.42.42.1'
      
      expect(subject.available_private_address_collection).to eq ["10.42.42.2", "10.42.42.3", "10.42.42.4", "10.42.42.5", "10.42.42.6"]
      
      subject.guests = [CloudModel::Guest.new(private_address: '10.42.42.6')]    
      
      expect(subject.available_private_address_collection).to eq ["10.42.42.2", "10.42.42.3", "10.42.42.4", "10.42.42.5"]
    end
    
    it 'should return empty array if no addresses available' do
      subject.private_network = '10.42.42.0/30'
      subject.private_network.gateway = '10.42.42.1'
       
      expect(subject.available_private_address_collection).to eq ['10.42.42.2']

      subject.guests = [
        CloudModel::Guest.new(private_address: '10.42.42.2')
      ]    
      
      expect(subject.available_private_address_collection).to eq []
    end
  end
  
  describe 'available_external_address_collection' do
    it 'should get the last available address from block' do
      subject.addresses << '192.168.42.0/30'
      
      expect(subject.available_external_address_collection).to eq ['192.168.42.1', '192.168.42.2']
      
      subject.guests = [CloudModel::Guest.new(external_address: '192.168.42.2')]    
      
      expect(subject.available_external_address_collection).to eq ['192.168.42.1']
    end
    
    it 'should return empty array if no addresses available' do
      subject.addresses << '192.168.42.0/30'
      
      expect(subject.dhcp_external_address).to eq '192.168.42.2'
      
      subject.guests = [
        CloudModel::Guest.new(external_address: '192.168.42.1'),
        CloudModel::Guest.new(external_address: '192.168.42.2')
      ]    
      
      expect(subject.available_external_address_collection).to eq []
    end
    
    it 'should only return IPv4 addresses' do
      subject.addresses << '192.168.42.0/30'
      subject.addresses << '2a01:4f8:160:9281::42/64'
      subject.addresses << '2a01:4f8:160:9281::43/64'
      subject.addresses << '2a01:4f8:160:9281::44/64'
      
      expect(subject.available_external_address_collection).to eq ['192.168.42.1', '192.168.42.2']
    end
  end

  describe 'dhcp_private_address' do
    it 'should get the last available address from block' do
      subject.private_network = '10.42.42.0/28'
      subject.private_network.gateway = '10.42.42.1'
      
      expect(subject.dhcp_private_address).to eq '10.42.42.14'
      
      subject.guests = [CloudModel::Guest.new(private_address: '10.42.42.14')]    
      
      expect(subject.dhcp_private_address).to eq '10.42.42.13'
    end
    
    it 'should return nil if no addresses available' do
      subject.private_network = '10.42.42.0/30'
      subject.private_network.gateway = '10.42.42.1'
      
      expect(subject.dhcp_private_address).to eq '10.42.42.2'
      
      subject.guests = [
        CloudModel::Guest.new(private_address: '10.42.42.2')
      ]    
      
      expect(subject.dhcp_private_address).to be_nil
    end
  end
  
  describe 'dhcp_external_address' do
    it 'should get the last available address from block' do
      subject.addresses << '192.168.42.0/28'
      
      expect(subject.dhcp_external_address).to eq '192.168.42.14'
      
      subject.guests = [CloudModel::Guest.new(external_address: '192.168.42.14')]    
      
      expect(subject.dhcp_external_address).to eq '192.168.42.13'
    end
    
    it 'should return nil if no addresses available' do
      subject.addresses << '192.168.42.0/30'
      
      expect(subject.dhcp_external_address).to eq '192.168.42.2'
      
      subject.guests = [
        CloudModel::Guest.new(external_address: '192.168.42.1'),
        CloudModel::Guest.new(external_address: '192.168.42.2')
      ]    
      
      expect(subject.dhcp_external_address).to be_nil
    end
    
    it 'should only return IPv4 addresses' do
      subject.addresses << '192.168.42.0/28'
      subject.addresses << '2a01:4f8:160:9281::42/64'
      subject.addresses << '2a01:4f8:160:9281::43/64'
      subject.addresses << '2a01:4f8:160:9281::44/64'
      
      expect(subject.dhcp_external_address).to eq '192.168.42.14'
    end
  end
  
  describe 'private_address' do
    it 'should return first address of private network' do
      subject.private_network = CloudModel::Address.new ip: '10.42.23.0', subnet: 24
      
      expect(subject.private_address).to eq '10.42.23.1'
    end
  end
  
  describe 'email_hostname' do
    pending
  end
  
  describe 'name_with_stage' do
    it 'should concatinate name with stage' do
      subject.name = 'some_host'
      subject.stage = :production
      
      expect(subject.name_with_stage).to eq '[production] some_host'
    end
  end
  
  describe 'tinc_private_key' do
    it 'should generate new key pair' do
      key = 'PRIVATE_KEY'
      allow(key).to receive(:public_key) { 'PUBLIC_KEY'}
      expect(OpenSSL::PKey::RSA).to receive(:new).and_return(key)
      
      expect(subject.tinc_private_key).to eq 'PRIVATE_KEY'
      expect(subject.tinc_public_key).to eq 'PUBLIC_KEY'
    end
  end
  
  describe 'ssh_connection' do
    it "should open a new SSH connection to the host on first call" do
      allow(CloudModel.config).to receive(:data_directory).and_return '/var/cloudmodel'
      expect(Net::SSH).to receive(:start).with(subject.primary_address.ip, "root", {keys: ["/var/cloudmodel/keys/id_rsa"], keys_only: true, password: ''}).and_return "SSH CONNECTION"
      expect(subject.ssh_connection).to eq "SSH CONNECTION"
    end
    
    it "should reuse SSH connection on further calls" do
      allow(CloudModel.config).to receive(:data_directory).and_return '/var/cloudmodel'
      allow(Net::SSH).to receive(:start).with(subject.primary_address.ip, "root", {keys: ["/var/cloudmodel/keys/id_rsa"], keys_only: true, password: ''}).and_return "SSH CONNECTION"      
      subject.ssh_connection
      expect(Net::SSH).not_to receive(:start)
      expect(subject.ssh_connection).to eq "SSH CONNECTION"
    end
  end
  
  describe 'sftp' do
    it 'should return the sftp of the ssh connection' do
      ssh_connection = double
      sftp_connection = double
      
      allow(subject).to receive(:ssh_connection).and_return ssh_connection
      expect(ssh_connection).to receive(:sftp).and_return sftp_connection
      
      expect(subject.sftp).to eq sftp_connection
    end
  end
  
  describe 'ssh_address' do
    it 'should return private address' do
      subject.private_network = '10.42.23.0/24'
      expect(subject.ssh_address).to eq '10.42.23.1'
    end
    
    it 'should return primary address if initial root pw is set' do
      subject.primary_address = '198.51.100.42'
      subject.initial_root_pw = 'P455w0rD'
      expect(subject.ssh_address).to eq '198.51.100.42'
    end    
  end
  
  describe 'shell' do
    # Goal is an interactive shell, but for now it puts ssh command to copy
    
    it 'should output the command to connect with ssh' do
      allow(CloudModel.config).to receive(:data_directory).and_return '/var/cloudmodel'
      allow(subject).to receive(:ssh_address).and_return '10.42.23.1'
      
      expect{ subject.shell }.to output("ssh -i /var/cloudmodel/keys/id_rsa root@10.42.23.1\n").to_stdout
    end
  end
  
  describe 'sync_inst_images' do
    it 'should call rsync for cloud directory' do
      allow(subject).to receive(:ssh_address).and_return '10.42.23.1'
      allow(CloudModel.config).to receive(:data_directory).and_return '/var/cloudmodel'
      allow(CloudModel.config).to receive(:skip_sync_images).and_return false
      allow(subject).to receive(:`).with("rsync -avz -e 'ssh -i /var/cloudmodel/keys/id_rsa' /var/cloudmodel/cloud/ root@10.42.23.1:/cloud").and_return("rsync result")
      
      expect(subject.sync_inst_images).to eq "rsync result"
    end
    
    
    it 'should skip sync if skip_sync_images config option is set' do
      allow(CloudModel.config).to receive(:skip_sync_images).and_return true
      
      expect(subject.sync_inst_images).to eq true
    end
  end
  
  describe 'exec', type: :ssh do
    let(:sftp_session) { double('Net::SFTP::Session', close_channel: true) }
    before do
      allow(subject).to receive(:sftp).and_return sftp_session
    end
    
    it 'should call exec on ssh_connection' do
      story_with_new_channel do |channel|
        channel.sends_exec "command"
        channel.gets_data "result of command"
        channel.gets_extended_data 'FAILURE'
        channel.gets_exit_status 0
      end
      
      script_with_connection do
        expect(subject.exec 'command').to eq [true, 'result of command']
      end
    end
    
    it 'should return success false if exec on ssh_connection fails' do
      story_with_new_channel do |channel|
        channel.sends_exec "command"
        channel.gets_data "result of command"
        channel.gets_extended_data 'FAILURE'
        channel.gets_exit_status 1
      end
  
      script_with_connection do
        expect(subject.exec 'command').to eq [false, "result of command\n\nFAILURE"]
      end
    end
    
    it 'should close sftp channel' do
      ssh_session = double 'Net::SSH::Session', open_channel: true, loop: true
      allow(subject).to receive(:ssh_connection).and_return ssh_session
      expect(sftp_session).to receive(:close_channel)
      expect(ssh_session).to receive(:instance_variable_set).with('@sftp', nil)
      subject.exec 'command'
    end
  end
  
  describe 'exec!' do
    it 'should call exec with same command' do
      expect(subject).to receive(:exec).with('command').and_return [true, 'true']
      expect(subject.exec! 'command', 'message').to eq 'true'
    end
    
    it 'should raise error with given message if exec fails' do
      expect(subject).to receive(:exec).with('command').and_return [false, 'An error occured']
      expect { subject.exec! 'command', 'message' }.to raise_error(RuntimeError, 'message: An error occured')
    end
  end
  
  describe 'mounted_at?' do
    it 'should return true if a filesystem is mounted at the given mountpoint' do
      mount = <<~OUT
        sysfs on /sys type sysfs (rw,relatime)
        proc on /proc type proc (rw,relatime)
        guests/custom/app on /var/lib/lxd/storage-pools/default/custom/app type zfs (rw,xattr,noacl)
      OUT
      
      expect(subject).to receive(:exec).with('mount').and_return [true, mount]
      
      expect(subject.mounted_at? '/var/lib/lxd/storage-pools/default/custom/app').to eq true
    end
  end
  
  describe 'boot_fs_mounted?' do
    it 'should return true if /boot is mounted' do
      expect(subject).to receive(:exec).with('mount').and_return [
        true, 
        "rootfs on / type rootfs (rw)\n" +
        "/dev/md126 on /boot type ext2 (rw,noatime)" +
        "proc on /proc type proc (rw,relatime)\n" +
        "udev on /dev type devtmpfs (rw,nosuid,relatime,size=10240k,nr_inodes=8144813,mode=755)\n"
      ]
      expect(subject.boot_fs_mounted?).to eq true
    end
    
    it 'should return false if /boot is not mounted' do
      expect(subject).to receive(:exec).with('mount').and_return [
        true, 
        "rootfs on / type rootfs (rw)\n" +
        "proc on /proc type proc (rw,relatime)\n" +
        "udev on /dev type devtmpfs (rw,nosuid,relatime,size=10240k,nr_inodes=8144813,mode=755)\n"
      ]
      expect(subject.boot_fs_mounted?).to eq false
    end
    
  end
  
  describe 'mount_boot_fs' do
    it 'should call mount if not mounted' do
      allow(subject).to receive(:boot_fs_mounted?).and_return false
        
      expect(subject).to receive(:exec).with('mkdir -p /boot && mount /dev/md0 /boot').and_return [true, 'success']
      expect(subject.mount_boot_fs).to eq true
    end

    it 'should not call mount if mounted' do
      allow(subject).to receive(:boot_fs_mounted?).and_return true
        
      expect(subject).not_to receive(:exec)
      expect(subject.mount_boot_fs).to eq true
    end
    
    it 'should fallback to rescue device if mount fails' do
      allow(subject).to receive(:boot_fs_mounted?).and_return false
        
      expect(subject).to receive(:exec).with('mkdir -p /boot && mount /dev/md0 /boot').and_return [false, 'fail']
      expect(subject).to receive(:exec).with('mount /dev/md/rescue:0 /boot').and_return [true, 'success']
      expect(subject.mount_boot_fs).to eq true
    end
    
    it 'should raise error if mount fails' do
      allow(subject).to receive(:boot_fs_mounted?).and_return false
        
      expect(subject).to receive(:exec).with('mkdir -p /boot && mount /dev/md0 /boot').and_return [false, 'fail']
      expect(subject).to receive(:exec).with('mount /dev/md/rescue:0 /boot').and_return [false, 'fail']
      expect(subject.mount_boot_fs).to eq false
    end
  end
  
  describe 'unmount_boot_fs' do
    it 'should call umount on host and return true on success' do
      expect(subject).to receive(:exec).with('umount /boot').and_return [true, '']
      
      expect(subject.unmount_boot_fs).to eq true
    end
  
    it 'should call umount on host and return false on failure success' do
      expect(subject).to receive(:exec).with('umount /boot').and_return [false, '']
      
      expect(subject.unmount_boot_fs).to eq false
    end
  end
  
  describe 'system_info' do
    pending
  end
  
  describe 'memory_size' do
    pending
  end
  
  describe 'cpu_usage' do
    pending
  end
  
  describe 'deployable?' do
    it 'should not be deployable if deploy state is :pending' do
      subject.deploy_state = :pending
      expect(subject).not_to be_deployable
    end
    
    it 'should not be deployable if deploy state is :running' do
      subject.deploy_state = :running
      expect(subject).not_to be_deployable
    end
    
    it 'should not be deployable if deploy state is :booting' do
      subject.deploy_state = :booting
      expect(subject).not_to be_deployable
    end
    
    it 'should be deployable if deploy state is :finished' do
      subject.deploy_state = :finished
      expect(subject).to be_deployable
    end
    
    it 'should be deployable if deploy state is :failed' do
      subject.deploy_state = :failed
      expect(subject).to be_deployable
    end
    
    it 'should be deployable if deploy state is :not_started' do
      subject.deploy_state = :not_started
      expect(subject).to be_deployable
    end
  end
  
  describe 'worker' do
    it 'should return worker for host' do
      worker = double CloudModel::Workers::HostWorker
      expect(CloudModel::Workers::HostWorker).to receive(:new).with(subject).and_return worker  
      
      expect(subject.worker).to eq worker
    end
  end
  
  describe 'deploy' do
    it 'should call rake cloudmodel:host:deploy with host´s id' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:host:deploy', host_id: subject.id)
      subject.deploy
    end 
    
    it 'should add an error if call_rake excepts' do
      allow(CloudModel).to receive(:call_rake).with('cloudmodel:host:deploy', host_id: subject.id).and_raise 'ERROR 42'
      subject.deploy
      expect(subject.deploy_state).to eq :failed
      expect(subject.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
    
    it 'should not call rake if not deployable' do
      expect(CloudModel).not_to receive(:call_rake).with('cloudmodel:host:deploy', host_id: subject.id)
      allow(subject).to receive(:deployable?).and_return false
      subject.deploy
    end
  end  
  
  describe 'deploy!' do
    it 'should call worker to deploy Host' do
      worker = double CloudModel::Workers::HostWorker, deploy: true
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
      worker = double CloudModel::Workers::HostWorker, deploy: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:deployable?).and_return false
      
      expect(subject.deploy! force:true).to eq true
    end
  end
  
  describe 'redeploy' do
    it 'should call rake cloudmodel:host:deploy with host´s id' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:host:redeploy', host_id: subject.id)
      subject.redeploy
    end 
    
    it 'should add an error if call_rake excepts' do
      allow(CloudModel).to receive(:call_rake).with('cloudmodel:host:redeploy', host_id: subject.id).and_raise 'ERROR 42'
      subject.redeploy
      expect(subject.deploy_state).to eq :failed
      expect(subject.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
    
    it 'should not call rake if not deployable' do
      expect(CloudModel).not_to receive(:call_rake).with('cloudmodel:host:redeploy', host_id: subject.id)
      allow(subject).to receive(:deployable?).and_return false
      subject.redeploy
    end
  end
  
  describe 'redeploy!' do
    it 'should call worker to deploy Host' do
      worker = double CloudModel::Workers::HostWorker, redeploy: true
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
      worker = double CloudModel::Workers::HostWorker, redeploy: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:deployable?).and_return false
      
      expect(subject.redeploy! force:true).to eq true
    end
  end
end