# encoding: UTF-8

require 'spec_helper'

describe CloudModel::SolrMirror do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:version).of_type String }
  it { expect(subject).to have_many(:solr_images).of_type CloudModel::SolrImage }
  it { expect(subject).to belong_to(:file).of_type(Mongoid::GridFS::Fs::File).with_optional }

  it { expect(subject).to validate_presence_of :version }
  it { expect(subject).to validate_uniqueness_of :version }

  describe 'original_file_url' do
    it 'should calculate download url for version on solr site' do
      subject.version = '8.5.0'
      expect(subject.original_file_url).to eq 'http://archive.apache.org/dist/lucene/solr/8.5.0/solr-8.5.0.tgz'
    end
  end

  describe 'local_filename' do
    it 'should return calculated archive name for version' do
      subject.version = '8.5.0'
      expect(subject.local_filename).to eq 'solr-8.5.0.tgz'
    end
  end

  describe 'update_file' do
    it 'should download file and store in GridFS' do
      tempfile = double Tempfile, path: '/tmp/test.tgz', binmode: nil
      allow(Tempfile).to receive(:new).and_return(tempfile)
      allow(subject).to receive(:`).and_return('')
      allow(subject).to receive(:original_file_url).and_return('http://example.com/solr.tgz')

      gridfs_file = double 'gridfs_file', id: 'new_id'
      allow(gridfs_file).to receive(:update_attribute)
      allow(Mongoid::GridFs).to receive(:put).with('/tmp/test.tgz').and_return(gridfs_file)
      allow(subject).to receive(:update_attribute)
      allow(subject).to receive(:file).and_return(nil)
      allow(tempfile).to receive(:close)
      allow(tempfile).to receive(:unlink)

      subject.update_file
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
end