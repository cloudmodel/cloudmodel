# encoding: UTF-8

require 'spec_helper'

describe CloudModel::SolrMirror do
  it { expect(subject).to have_timestamps }
  
  it { expect(subject).to have_field(:version).of_type String }
  it { expect(subject).to have_many(:solr_images).of_type CloudModel::SolrImage }
  it { expect(subject).to belong_to(:file).of_type Mongoid::GridFS::Fs::File }
  
  it { expect(subject).to validate_presence_of :version }
  it { expect(subject).to validate_uniqueness_of :version }
  
  context 'original_file_url' do
    it 'should calculate download url for version on solr site' do
      subject.version = '8.5.0'
      expect(subject.original_file_url).to eq 'http://archive.apache.org/dist/lucene/solr/8.5.0/solr-8.5.0.tgz'
    end
  end
  
  context 'local_filename' do
    it 'should return calculated archive name for version' do
      subject.version = '8.5.0'
      expect(subject.local_filename).to eq 'solr-8.5.0.tgz'
    end
  end
  
  context 'update_file' do
    pending
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
end