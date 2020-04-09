# encoding: UTF-8

require 'spec_helper'

describe CloudModel::WarImage do
  it { expect(subject).to have_timestamps }  
    
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to belong_to(:file).of_type Mongoid::GridFS::Fs::File }

  it { expect(subject).to validate_presence_of :name }
  it { expect(subject).to validate_presence_of :file }
  it { expect(subject).to validate_uniqueness_of :name }

  describe 'used_in_guests' do
    it 'should get all guests that has Services using this Certificate' do
      expect(CloudModel::Guest).to receive(:where).with('services.deploy_war_image_id' => subject.id).and_return 'LIST OF GUESTS'
      expect(subject.used_in_guests).to eq 'LIST OF GUESTS'
    end
  end

  describe 'used_in_guests_by_hosts' do
    it 'should sort the result of used_in_guests by host and return a Hash' do
      guests = [
        double(CloudModel::Guest, host_id: 'host1'),
        double(CloudModel::Guest, host_id: 'host2'),
        double(CloudModel::Guest, host_id: 'host1')        
      ]    
      allow(subject).to receive(:used_in_guests).and_return guests
      
      expect(subject.used_in_guests_by_hosts).to eq({
        'host1' => [guests[0], guests[2]],
        'host2' => [guests[1]],
      })
    end
  end

  describe 'file_size' do
    it 'should get length from file object' do
      subject.file = Mongoid::GridFS::Fs::File.new
      subject.file.length = 4711
      expect(subject.file_size).to eq 4711
    end
    
    it 'should be nil if no file was attached' do
      subject.file = nil
      expect(subject.file_size).to be_nil
    end
  end

  describe 'file_upload' do
    it 'should upload and assign new GridFs file' do
      uploaded = double 'Upload', tempfile: double(Tempfile, path: '/test.war_image')
      file = double Mongoid::GridFs, id: '42'
      
      expect(Mongoid::GridFs).to receive(:put).with('/test.war_image').and_return file
      subject.file_upload = uploaded
      expect(subject.file_id).to eq '42'
    end
  end
end