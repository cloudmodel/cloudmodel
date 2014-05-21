# encoding: UTF-8

require 'spec_helper'

describe CloudModel::LogicalVolume do
  before do
    CloudModel::VolumeGroup.any_instance.stub(:apply_create).and_return true
  end
  
  it { expect(subject).to be_timestamped_document }  

  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:disk_space).of_type(Integer).with_default_value_of 10*1024*1024*1024 }
  it { expect(subject).to have_field(:disk_format).of_type(String).with_default_value_of 'ext4' }

  it { expect(subject).to belong_to(:volume_group).of_type CloudModel::VolumeGroup }
  it { expect(subject).to belong_to(:guest).of_type CloudModel::Guest}
  it { expect(subject).to have_many(:guest_volumes).of_type CloudModel::GuestVolume }  
  
  it { expect(subject).to validate_presence_of(:volume_group) }
  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name).scoped_to(:volume_group) }
  it { expect(subject).to validate_format_of(:name).to_allow("vg0").not_to_allow("Test VG") }

  it { expect(subject).to validate_presence_of(:disk_space) }
  it { expect(subject).to validate_presence_of(:disk_format) }
  
  context 'disk_space=' do
    it 'should parse input as size string' do
      expect(subject).to receive(:accept_size_string_parser).with('Size String').and_return(42)
      subject.disk_space = 'Size String'
      
      expect(subject.disk_space).to eq 42
    end
  end
  
  context 'to_param' do
    it 'should have name as param' do
      subject.name = 'blafasel'
      expect(subject.to_param).to eq 'blafasel'
    end
  end
  
  context 'device' do
    it 'should get device name out of own name and vg name' do
      subject.name = 'test-device'
      subject.volume_group = CloudModel::VolumeGroup.new name: 'test-group'
      expect(subject.device).to eq '/dev/test-group/test-device'
    end
  end
  
  context 'mapper_device' do
    it 'should get device mapper name out of own name and vg name' do
      subject.name = 'test-device'
      subject.volume_group = CloudModel::VolumeGroup.new name: 'test-group'
      expect(subject.mapper_device).to eq '/dev/mapper/test--group-test--device'
    end
  end
  
  context 'real_info' do
    it 'should get real_info from VolumeGroup' do
      subject.name = 'test_device'
      subject.volume_group = CloudModel::VolumeGroup.new name: 'test-group'
      
      subject.volume_group.should_receive(:list_real_volumes).and_return({
        root: 'Root LV info',
        test_device: 'My LV info',
        other: 'Other LV info'
      })
      
      expect(subject.real_info).to eq "My LV info"
    end
  end
  
  context 'exec' do
    it 'should pass thru to host exec' do
      host = CloudModel::Host.new
      subject.volume_group = CloudModel::VolumeGroup.new name: 'test-group', host: host
      host.should_receive(:exec).with('command').and_return [true, 'success']
      expect(subject.exec 'command').to eq [true, 'success']
    end
  end
  
  context 'apply' do  
    subject { CloudModel::LogicalVolume.new volume_group: Factory(:volume_group, name: 'vg0') }
     
    it 'should be called after safe' do
      subject.name = 'test_lv'
      subject.should_receive(:apply).and_return true
      subject.save!
    end
    
    it 'should create and format a new LV if not exists' do
      subject.name = 'test_lv'
      subject.stub(:real_info).and_return nil
      subject.volume_group.stub(:device).and_return('/vg42')
      subject.stub(:device).and_return('/vg42/lv23')
      subject.disk_space = 2048
      
      subject.should_receive(:exec).with('lvcreate -L 2048b -n test_lv /vg42').once.and_return(true, '')
      subject.should_receive(:exec).with('mkfs.ext4 /vg42/lv23').and_return(true, '')
      
      subject.apply
    end
    
    it 'should escape on create mode' do
      subject.name = 'test_lv'
      subject.stub(:real_info).and_return nil
      subject.volume_group.stub(:device).and_return('/;rm -rf;')
      subject.stub(:device).and_return(';mkfs /dev/sda;')
      subject.disk_space = ';halt;'
      
      subject.should_receive(:exec).with('lvcreate -L 10737418240b -n test_lv /\\;rm\\ -rf\\;').and_return(true, '')
      subject.should_receive(:exec).with('mkfs.ext4 \\;mkfs\\ /dev/sda\\;').and_return(true, '')
      
      subject.apply
    end
    
    it 'should shrink volume if new disc size is smaller than actual' do
      subject.stub(:real_info).and_return({l_size: 4096})
      subject.volume_group.stub(:device).and_return('/vg42')
      subject.stub(:device).and_return('/vg42/lv23')
      subject.disk_space = 2048
    
      subject.should_receive(:exec).with('e2fsck -f /vg42/lv23 && resize2fs /vg42/lv23 2K').and_return(true, '')
      subject.should_receive(:exec).with('lvreduce /vg42/lv23 --size 2048b -f').and_return(true, '')
      
      subject.apply
    end
    
    it 'should escape on shrink mode' do
      subject.stub(:real_info).and_return({l_size: 4096})
      subject.volume_group.stub(:device).and_return('/;rm -rf;')
      subject.stub(:device).and_return(';mkfs /dev/sda;')
      subject.disk_space = 1024
    
      subject.should_receive(:exec).with('e2fsck -f \\;mkfs\\ /dev/sda\\; && resize2fs \\;mkfs\\ /dev/sda\\; 1K').and_return(true, '')
      subject.should_receive(:exec).with('lvreduce \\;mkfs\\ /dev/sda\\; --size 1024b -f').and_return(true, '')
      
      subject.apply
    end
    
    it 'should grow volume if new disc size is bigger than actual' do
      subject.stub(:real_info).and_return({l_size: 1024})
      subject.volume_group.stub(:device).and_return('/vg42')
      subject.stub(:device).and_return('/vg42/lv23')
      subject.disk_space = 2048
    
      subject.should_receive(:exec).with('lvextend /vg42/lv23 --size 2048b').and_return(true, '')
      subject.should_receive(:exec).with('resize2fs /vg42/lv23').and_return(true, '')
      
      subject.apply
    end

    it 'should should escape on grow mode' do
      subject.stub(:real_info).and_return({l_size: 1024})
      subject.volume_group.stub(:device).and_return('/;rm -rf;')
      subject.stub(:device).and_return(';mkfs /dev/sda;')
      subject.disk_space = ';halt;'
    
      subject.should_receive(:exec).with('lvextend \\;mkfs\\ /dev/sda\\; --size 10737418240b').and_return(true, '')
      subject.should_receive(:exec).with('resize2fs \\;mkfs\\ /dev/sda\\;').and_return(true, '')
      
      subject.apply
    end
    
    it 'should leave the volume untouched if size does not change' do
      subject.stub(:real_info).and_return({l_size: 2048})
      subject.volume_group.stub(:device).and_return('/vg42')
      subject.stub(:device).and_return('/vg42/lv23')
      subject.disk_space = 2048
    
      subject.should_not_receive(:exec)
      
      subject.apply
    end
  end
  
  context 'apply_destroy' do
    it 'should be called before destroy' do
      subject.should_receive(:apply_destroy).and_return true
      subject.destroy
    end
    
    it 'should call `lvremove` if lv exist' do
      subject.stub(:real_info).and_return({info: true})
      subject.stub(:device).and_return('/vg42/lv23')
      
      subject.should_receive(:exec).with('lvremove -f /vg42/lv23').and_return(true, '')
      
      subject.apply_destroy
    end
    
    it 'should escape parameters passed to ssh exec' do 
      subject.stub(:real_info).and_return({info: true})
      subject.stub(:device).and_return('; rm -rf /;')

      subject.should_receive(:exec).with('lvremove -f \\;\\ rm\\ -rf\\ /\\;').and_return(true, '')
      
      subject.apply_destroy
    end
    
    it 'should not call ssh if device not found in real_info' do
      subject.stub(:real_info).and_return nil
      subject.should_not_receive(:exec)
      
      subject.apply_destroy
    end
  end
  
  context 'mount' do
    it 'should call mount on the host connected by volume_group' do
      host = Factory :host
      subject.volume_group = Factory :volume_group, host: host, name: 'vg0'
      subject.name = 'test'
      subject.disk_format = 'ext4'
      ssh_connection = double 'SSHConnection', exec: '--- dom info ---'
      subject.should_receive(:mounted_on?).with('/mnt/test').and_return false
      host.should_receive(:exec).with('mkdir -p /mnt/test && mount -t ext4 -o noatime /dev/vg0/test /mnt/test').and_return [true, 'mounted']
      
      expect(subject.mount '/mnt/test').to eq true
    end
    
    it 'should escape parameters on call' do
      host = Factory :host
      subject.volume_group = Factory :volume_group, host: host
      subject.volume_group.stub(:device).and_return '/dev/vg0; rm -rf /;'
      subject.stub(:name).and_return 'test; reboot;'
      subject.disk_format = 'ext4; do evil;'
      ssh_connection = double 'SSHConnection', exec: '--- dom info ---'
      subject.should_receive(:mounted_on?).with('/mnt/test; cat /dev/random /dev/sda;').and_return false
      host.should_receive(:exec).with('mkdir -p /mnt/test\\;\\ cat\\ /dev/random\\ /dev/sda\\; && mount -t ext4\\;\\ do\\ evil\\; -o noatime /dev/vg0\\;\\ rm\\ -rf\\ /\\;/test\\;\\ reboot\\; /mnt/test\\;\\ cat\\ /dev/random\\ /dev/sda\\;').and_return [true, 'mounted']
      
      subject.mount '/mnt/test; cat /dev/random /dev/sda;'
    end
    
  end
end