# encoding: UTF-8

require 'spec_helper'

describe CloudModel::WarImage do
  it { expect(subject).to be_timestamped_document }  
    
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to belong_to(:file).of_type Mongoid::GridFS::Fs::File }

  it { expect(subject).to validate_presence_of :name }
  it { expect(subject).to validate_presence_of :file }
  it { expect(subject).to validate_uniqueness_of :name }

  context 'used_in_guests' do
    it 'should get all guests that has Services using this Certificate' do
      CloudModel::Guest.should_receive(:where).with('services.deploy_war_image_id' => subject.id).and_return 'LIST OF GUESTS'
      expect(subject.used_in_guests).to eq 'LIST OF GUESTS'
    end
  end

  context 'used_in_guests_by_hosts' do
    it 'should sort the result of used_in_guests by host and return a Hash' do
      guests = [
        mock_model(CloudModel::Guest, host_id: 'host1'),
        mock_model(CloudModel::Guest, host_id: 'host2'),
        mock_model(CloudModel::Guest, host_id: 'host1')        
      ]    
      subject.stub(:used_in_guests) { guests }
      
      expect(subject.used_in_guests_by_hosts).to eq({
        'host1' => [guests[0], guests[2]],
        'host2' => [guests[1]],
      })
    end
  end

  context 'file_size' do
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

  context 'file_upload' do
    it 'should upload and assign new GridFs file' do
      uploaded = double 'Upload', tempfile: double(Tempfile, path: '/test.war_image')
      file = double Mongoid::GridFs, id: '42'
      
      Mongoid::GridFs.should_receive(:put).with('/test.war_image').and_return file
      subject.file_upload = uploaded
      expect(subject.file_id).to eq '42'
    end
  end
end