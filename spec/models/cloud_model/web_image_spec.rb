# encoding: UTF-8

require 'spec_helper'

describe CloudModel::WebImage do
  it { expect(subject).to be_timestamped_document }  
    
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:git_server).of_type String }
  it { expect(subject).to have_field(:git_repo).of_type String }
  it { expect(subject).to have_field(:git_branch).of_type(String).with_default_value_of 'master' }
  it { expect(subject).to have_field(:git_commit).of_type String }
  it { expect(subject).to have_field(:has_assets).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:has_mongodb).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:has_redis).of_type(Mongoid::Boolean).with_default_value_of false }

  it { expect(subject).to belong_to(:file).of_type Mongoid::GridFS::Fs::File }

  it { expect(subject).to validate_presence_of :name }
  it { expect(subject).to validate_presence_of :git_server }
  it { expect(subject).to validate_presence_of :git_repo }
  it { expect(subject).to validate_presence_of :git_branch }
  it { expect(subject).to validate_uniqueness_of :name }

  context 'used_in_guests' do
    it 'should get all guests that has Services using this Certificate' do
      CloudModel::Guest.should_receive(:where).with('services.deploy_web_image_id' => subject.id).and_return 'LIST OF GUESTS'
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

  context 'build_path' do   
    it 'should build in CloudModel data_directory' do
      CloudModel.config.stub(:data_directory).and_return Pathname.new '/my_home/rails_project/data'
      
      expect(subject.build_path).to eq "/my_home/rails_project/data/build/web_images/#{subject.id}"
    end
  end

  context 'build_gem_home' do
    it 'should give path to gem_home of deployed WebImage' do
      subject.stub(:build_path).and_return '/tmp/build/master'
      Bundler.stub(:ruby_scope).and_return 'ruby/4.2.0'
      
      expect(subject.build_gem_home).to eq '/tmp/build/master/shared/bundle/ruby/4.2.0'
    end
    
  end

  context 'build_gemfile' do
    it 'should give path to Gemfile of deployed WebImage' do
      subject.stub(:build_path).and_return '/tmp/build/master'
      expect(subject.build_gemfile).to eq '/tmp/build/master/current/Gemfile'
    end
  end
end