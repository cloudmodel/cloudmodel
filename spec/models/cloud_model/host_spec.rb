# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Host do
  it { expect(subject).to be_timestamped_document }  
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:tinc_public_key).of_type String }
  it { expect(subject).to have_field(:initial_root_pw).of_type String }
  
  it { expect(subject).to have_enum(:stage).with_values(
    0x00 => :pending,
    0x10 => :testing,
    0x30 => :staging,
    0x40 => :production,
  ).with_default_value_of(:pending) }
  
  it { expect(subject).to have_enum(:deploy_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0x02 => :booting,
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
  it { expect(subject).to have_many(:volume_groups).of_type CloudModel::VolumeGroup }
  it { expect(subject).to accept_nested_attributes_for(:volume_groups) }
  
  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name) }
  it { expect(subject).to validate_format_of(:name).to_allow("host-name-01").not_to_allow("Test Host") }
  it { expect(subject).to validate_presence_of(:primary_address) }
  it { expect(subject).to validate_presence_of(:private_network) }
  
  context 'addresses=' do
    it 'should accept strings to be added' do
      subject.addresses << CloudModel::Address.new(ip: '10.42.23.11', subnet: 26)
      subject.addresses << '192.168.42.1/28'
      expect(subject.addresses.size).to eq 2
      subject.addresses.map(&:class).should == [CloudModel::Address, CloudModel::Address]
      subject.addresses.map(&:to_s).should == ['10.42.23.11/26', '192.168.42.1/28']
    end
    
    it 'should accept strings as initial array' do
      subject.addresses << '10.23.0.42/29'
      subject.addresses = [CloudModel::Address.new(ip: '10.42.23.11', subnet: 26), '192.168.42.1/28']
      expect(subject.addresses.size).to eq 2
      subject.addresses.map(&:class).should == [CloudModel::Address, CloudModel::Address]
      subject.addresses.map(&:to_s).should == ['10.42.23.11/26', '192.168.42.1/28']
    end
    
    it 'should accept hashes to be added' do
      subject.addresses << CloudModel::Address.new(ip: '10.42.23.11', subnet: 26)
      subject.addresses << {ip: '192.168.42.1', subnet: 28}
      expect(subject.addresses.size).to eq 2
      subject.addresses.map(&:class).should == [CloudModel::Address, CloudModel::Address]
      subject.addresses.map(&:to_s).should == ['10.42.23.11/26', '192.168.42.1/28']
    end
    
    it 'should accept hashes as initial array' do
      subject.addresses << {ip: '10.23.0.42', subnet: 29}
      subject.addresses = [CloudModel::Address.new(ip: '10.42.23.11', subnet: 26), '192.168.42.1/28']
      expect(subject.addresses.size).to eq 2
      subject.addresses.map(&:class).should == [CloudModel::Address, CloudModel::Address]
      subject.addresses.map(&:to_s).should == ['10.42.23.11/26', '192.168.42.1/28']
    end
  end
  
  context 'primary_address=' do
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
  
  context 'private_network=' do    
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
  
  context 'available_private_address_collection' do
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
  
  context 'available_external_address_collection' do
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

  context 'dhcp_private_address' do
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
  
  context 'dhcp_external_address' do
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
  
  context 'tinc_private_key' do
    it 'should generate new key pair' do
      key = 'PRIVATE_KEY'
      key.stub(:public_key) { 'PUBLIC_KEY'}
      OpenSSL::PKey::RSA.should_receive(:new).and_return(key)
      
      expect(subject.tinc_private_key).to eq 'PRIVATE_KEY'
      expect(subject.tinc_public_key).to eq 'PUBLIC_KEY'
    end
  end
  
  it 'should have name as param' do
    subject.name = 'blafasel'
    expect(subject.to_param).to eq 'blafasel'
  end
  
  context 'ssh_conncetion' do
    it "should open a new SSH connection to the host on first call" do
      Net::SSH.should_receive(:start).with(subject.primary_address.ip, "root").and_return "SSH CONNECTION"
      expect(subject.ssh_connection).to eq "SSH CONNECTION"
    end
    
    it "should reuse SSH connection on further calls" do
      Net::SSH.stub(:start).with(subject.primary_address.ip, "root").and_return "SSH CONNECTION"      
      subject.ssh_connection
      Net::SSH.should_not_receive(:start).with(subject.primary_address.ip, "root")
      expect(subject.ssh_connection).to eq "SSH CONNECTION"
    end
  end
  
  context 'exec' do
    it 'should call exec on ssh_connection' do
      ssh_connection = double 'SSHConnection', exec: '--- dom info ---'
      subject.should_receive(:ssh_connection).and_return ssh_connection
      ssh_connection.should_receive(:exec!).with('command').and_yield(nil, :stderr, 'error occured')
      subject.exec 'command'
    end
    
    it 'should return success false if exec on ssh_connection fails' do
      ssh_connection = double 'SSHConnection', exec: '--- dom info ---'
      subject.should_receive(:ssh_connection).and_return ssh_connection
      ssh_connection.should_receive(:exec!).with('command').and_yield(nil, :stdio, 'ok')
      expect(subject.exec 'command').to eq [true, "ok"]
    end
    
    it 'should return success false if exec on ssh_connection fails' do
      ssh_connection = double 'SSHConnection', exec: '--- dom info ---'
      subject.should_receive(:ssh_connection).and_return ssh_connection
      ssh_connection.should_receive(:exec!).with('command').and_yield(nil, :stderr, 'error occured')
      expect(subject.exec 'command').to eq [false, "error occured"]
    end
  end
  
  context 'exec!' do
    it 'should call exec with same command' do
      subject.should_receive(:exec).with('command').and_return [true, 'true']
      expect(subject.exec! 'command', 'message').to eq 'true'
    end
    
    it 'should raise error with given message if exec fails' do
      subject.should_receive(:exec).with('command').and_return [false, 'An error occured']
      expect { subject.exec! 'command', 'message' }.to raise_error(RuntimeError, 'message: An error occured')
    end
  end
  
  context 'boot_fs_mounted?' do
    it 'should return true if /boot is mounted' do
      subject.should_receive(:exec).with('mount').and_return [
        true, 
        "rootfs on / type rootfs (rw)\n" +
        "/dev/md126 on /boot type ext2 (rw,noatime)" +
        "proc on /proc type proc (rw,relatime)\n" +
        "udev on /dev type devtmpfs (rw,nosuid,relatime,size=10240k,nr_inodes=8144813,mode=755)\n"
      ]
      expect(subject.boot_fs_mounted?).to be_true
    end
    
    it 'should return false if /boot is not mounted' do
      subject.should_receive(:exec).with('mount').and_return [
        true, 
        "rootfs on / type rootfs (rw)\n" +
        "proc on /proc type proc (rw,relatime)\n" +
        "udev on /dev type devtmpfs (rw,nosuid,relatime,size=10240k,nr_inodes=8144813,mode=755)\n"
      ]
      expect(subject.boot_fs_mounted?).to be_false
    end
    
  end
  
  context 'mount_boot_fs' do
    it 'should call mount if not mounted' do
      subject.stub(:boot_fs_mounted?).and_return false
        
      subject.should_receive(:exec).with('mount "/dev/md127" /boot').and_return [true, 'success']
      expect(subject.mount_boot_fs).to be_true
    end

    it 'should not call mount if mounted' do
      subject.stub(:boot_fs_mounted?).and_return true
        
      subject.should_not_receive(:exec).with('mount "/dev/md127" /boot')
      expect(subject.mount_boot_fs).to be_true
    end
    
    it 'should fallback to rescue device if mount fails' do
      subject.stub(:boot_fs_mounted?).and_return false
        
      subject.should_receive(:exec).with('mount "/dev/md127" /boot').and_return [false, 'fail']
      subject.should_receive(:exec).with('mount "/dev/md/rescue:127" /boot').and_return [true, 'success']
      expect(subject.mount_boot_fs).to be_true
    end
    
    it 'should raise error if mount fails' do
      subject.stub(:boot_fs_mounted?).and_return false
        
      subject.should_receive(:exec).with('mount "/dev/md127" /boot').and_return [false, 'fail']
      subject.should_receive(:exec).with('mount "/dev/md/rescue:127" /boot').and_return [false, 'fail']
      expect(subject.mount_boot_fs).to be_false
    end
  end
  
  context 'list_real_volume_groups' do
    let(:ssh_connection) { double 'SSHConnection' }
    
    before do
      subject.stub(:ssh_connection).and_return ssh_connection
    end

    it 'should call vgs on host' do
      ssh_connection.should_receive(:exec!).with('vgs --separator \';\' --units b --all --nosuffix -o vg_all').and_return(
        "  Fmt;VG UUID;VG\n" +
        "  lvm2;4jM5nB-lV98-rFwR-4fWc-cwF4-dwdf-Fw3rsa;vg0\n"
      )
      subject.list_real_volume_groups
    end
    
    it 'should parse return value of vgs' do
      subject.should_receive(:exec).with('vgs --separator \';\' --units b --all --nosuffix -o vg_all').and_return([
        true,
        "  Fmt;VG UUID;VG;Attr;VSize;VFree;SYS ID;Ext;#Ext;Free;MaxLV;MaxPV;#PV;#LV;#SN;Seq;VG Tags;VProfile;#VMda;#VMdaUse;VMdaFree;VMdaSize;#VMdaCps\n" +
        "  lvm2;4jM5nB-lV98-rFwR-4fWc-cwF4-dwdf-Fw3rsa;vg0;wz--n-;2965960130560;2746916798464;;4194304;707140;654916;0;0;1;16;0;41;;;1;1;90112;192512;unmanaged\n"
      ])
      expect(subject.list_real_volume_groups).to eq({
        vg0: {
          fmt: 'lvm2', 
          vg_uuid: '4jM5nB-lV98-rFwR-4fWc-cwF4-dwdf-Fw3rsa', 
          attr: 'wz--n-', 
          v_size: '2965960130560', 
          v_free: '2746916798464', 
          sys_id: '', 
          ext: '707140', 
          free: '654916', 
          max_lv: '0', 
          max_pv: '0', 
          pv: '1', 
          lv: '16', 
          sn: '0', 
          seq: '41', 
          vg_tags: '', 
          v_profile: '', 
          v_mda: '1', 
          v_mda_use: '1', 
          v_mda_free: '90112', 
          v_mda_size: '192512', 
          v_mda_cps: 'unmanaged'
        }
      })
    end
  end
  
  context 'deployable?' do
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
  
  context 'deploy' do
    it 'should call rake cloudmodel:host:deploy with host´s id' do
      CloudModel.should_receive(:call_rake).with('cloudmodel:host:deploy', host_id: subject.id)
      subject.deploy
    end 
    
    it 'should add an error if call_rake excepts' do
      CloudModel.stub(:call_rake).with('cloudmodel:host:deploy', host_id: subject.id).and_raise 'ERROR 42'
      subject.deploy
      expect(subject.deploy_state).to eq :failed
      expect(subject.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
    
    it 'should not call rake if not deployable' do
      CloudModel.should_not_receive(:call_rake).with('cloudmodel:host:deploy', host_id: subject.id)
      subject.stub(:deployable?).and_return false
      subject.deploy
    end
  end  
  
  context 'redeploy' do
    it 'should call rake cloudmodel:host:deploy with host´s id' do
      CloudModel.should_receive(:call_rake).with('cloudmodel:host:redeploy', host_id: subject.id)
      subject.redeploy
    end 
    
    it 'should add an error if call_rake excepts' do
      CloudModel.stub(:call_rake).with('cloudmodel:host:redeploy', host_id: subject.id).and_raise 'ERROR 42'
      subject.redeploy
      expect(subject.deploy_state).to eq :failed
      expect(subject.deploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
    
    it 'should not call rake if not deployable' do
      CloudModel.should_not_receive(:call_rake).with('cloudmodel:host:redeploy', host_id: subject.id)
      subject.stub(:deployable?).and_return false
      subject.redeploy
    end
  end
end