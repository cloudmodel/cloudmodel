# encoding: UTF-8

require 'spec_helper'

describe CloudModel::VolumeGroup do
  it { should be_timestamped_document }  

  it { should belong_to(:host).of_type CloudModel::Host }
  it { should have_many(:logical_volumes).of_type CloudModel::LogicalVolume }
  
  it { should have_field(:name).of_type String }
  it { should have_field(:disk_space).of_type(Integer) }
  it { should have_field(:disk_device).of_type(String) }
  
  it { should validate_presence_of(:name) }
  it { should validate_uniqueness_of(:name).scoped_to(:host) }
  it { should validate_format_of(:name).to_allow("vg0").not_to_allow("Test VG") }

  it { should validate_presence_of(:disk_device) }
  
  context 'disk_space=' do
    it 'should parse input as size string' do
      expect(subject).to receive(:accept_size_string_parser).with('Size String').and_return(42)
      subject.disk_space = 'Size String'
      
      expect(subject.disk_space).to eq 42
    end
  end
  
  context 'available_space' do
    it 'should calculate available space' do
      subject.disk_space = '20 KiB'
      subject.name = 'vg0'
      subject.disk_device = 'md0'
      
      subject.logical_volumes.should_receive(:sum).with(:disk_space).and_return(8192)
      
      subject.available_space.should == 12*2**10
    end
  end
  
  context 'device' do
    it 'should return device named like :name' do
      subject.name = 'nirvana'
      expect(subject.device).to eq '/dev/nirvana'
    end
  end
  
  context 'to_param' do
    it 'should have name as param' do
      subject.name = 'blafasel'
      subject.to_param.should == 'blafasel'
    end
  end
  
  
  context 'real_info' do
    it 'should get real_info from Host' do
      subject.name = 'test_device'
      subject.host = CloudModel::Host.new name: 'test-host'
      
      subject.host.should_receive(:list_real_volume_groups).and_return({
        root: 'Root VG info',
        test_device: 'My VG info',
        other: 'Other VG info'
      })
      
      expect(subject.real_info).to eq "My VG info"
    end
  end
  context 'real_info' do
    it 'should send list_real_volume_groups to host ' do
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
  
  context 'list_real_volumes' do
    before do
      subject.name = 'vg0'
      subject.host = Factory :host
    end

    it 'should call vgs on host' do
      subject.should_receive(:exec).with('lvs --separator \';\' --units b --nosuffix --all -o lv_all vg0').and_return([
        true,
        "  LV UUID;LV\n" +
        "  Fw3rsa-rFwR-cwF4-ceOn-Tc4r-dwdf-5m2nn2k;root\n"
      ])
      subject.list_real_volumes
    end
    
    it 'should parse return value of vgs' do
      subject.should_receive(:exec).with('lvs --separator \';\' --units b --nosuffix --all -o lv_all vg0').and_return([
        true,
        "  LV UUID;LV;Path;Attr;Active;Maj;Min;Rahead;KMaj;KMin;KRahead;LSize;MSize;#Seg;Origin;OSize;Data%;Snap%;Meta%;Cpy%Sync;Cpy%Sync;Mismatches;SyncAction;WBehind;MinSync;MaxSync;Move;Convert;Log;Data;Meta;Pool;LV Tags;LProfile;Time;Host;Modules\n" +
        "  Fw3rsa-rFwR-cwF4-ceOn-Tc4r-dwdf-5m2nn2k;root;/dev/vg0/root;-wi-a-----;active;-1;-1;auto;253;7;131072;10737418240;;1;;;;;;;;;;;;;;;;;;;;;2010-09-08 19:03:51 +0200;srv01;\n"
      ])

      expect(subject.list_real_volumes).to eq({
        :root=>{
          lv_uuid: 'Fw3rsa-rFwR-cwF4-ceOn-Tc4r-dwdf-5m2nn2k', 
          path: '/dev/vg0/root', 
          attr: '-wi-a-----', 
          active: 'active', 
          maj: '-1', 
          min: '-1', 
          rahead: 'auto', 
          k_maj: '253', 
          k_min: '7', 
          k_rahead: '131072', 
          l_size: '10737418240', 
          m_size: '', 
          seg: '1', 
          origin: '', 
          o_size: '', 
          data_percentage: '', 
          snap_percentage: '', 
          meta_percentage: '', 
          cpy_percentage_sync: '', 
          mismatches: '', 
          sync_action: '', 
          w_behind: '', 
          min_sync: '', 
          max_sync: '', 
          move: '', 
          convert: '', 
          log: '', 
          data: '', 
          meta: '', 
          pool: '', 
          lv_tags: '', 
          l_profile: '', 
          time: '2010-09-08 19:03:51 +0200', 
          host: 'srv01'
        }
      })
    end
  end
end