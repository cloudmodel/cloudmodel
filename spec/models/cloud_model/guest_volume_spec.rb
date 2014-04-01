# encoding: UTF-8

require 'spec_helper'

describe CloudModel::GuestVolume do
  it { expect(subject).to be_timestamped_document }  
  
  it { expect(subject).to belong_to(:guest).of_type CloudModel::Guest }
  it { expect(subject).to belong_to(:logical_volume).of_type CloudModel::LogicalVolume }
  it { expect(subject).to accept_nested_attributes_for :logical_volume}

  it { expect(subject).to validate_presence_of(:guest) }
  it { expect(subject).to validate_presence_of(:logical_volume) }

  it { expect(subject).to have_field(:mount_point).of_type String }
  it { expect(subject).to validate_presence_of(:mount_point) }
  it { expect(subject).to validate_uniqueness_of(:mount_point).scoped_to(:guest) }
  it { expect(subject).to validate_format_of(:mount_point).to_allow("data/db").not_to_allow("/etc").not_to_allow("tmp/../../etc") }
  
  it { expect(subject).to have_field(:writeable).of_type(Mongoid::Boolean).with_default_value_of true }

  context 'set_volume_name' do
    it 'should set name on logical volume' do
      subject.guest = CloudModel::Guest.new name: 'guest42'
      subject.mount_point = '/data/hgtg'
      subject.send(:set_volume_name)
      expect(subject.logical_volume.name).to eq 'guest42--data-hgtg'
    end
    
    it 'should be called on validations' do
      expect(subject).to receive(:set_volume_name)
      subject.valid?
    end
  end
end