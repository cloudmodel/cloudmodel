# encoding: UTF-8

require 'spec_helper'

describe CloudModel::SolrImage do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:git_server).of_type String }
  it { expect(subject).to have_field(:git_repo).of_type String }
  it { expect(subject).to have_field(:git_branch).of_type(String).with_default_value_of 'master' }
  it { expect(subject).to have_field(:git_commit).of_type String }
  it { expect(subject).to have_field(:solr_version).of_type String }

  it { expect(subject).to have_enum(:build_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0x02 => :checking_out,
    0x05 => :packaging,
    0x06 => :storing,
    0xf0 => :finished,
    0xf1 => :failed,
    0xff => :not_started
  ).with_default_value_of(:not_started) }
  it { expect(subject).to have_field(:build_last_issue).of_type(String) }

  it { expect(subject).to belong_to(:file).of_type(Mongoid::GridFS::Fs::File).with_optional }

  it { expect(subject).to validate_presence_of :name }
  it { expect(subject).to validate_presence_of :git_server }
  it { expect(subject).to validate_presence_of :git_repo }
  it { expect(subject).to validate_presence_of :git_branch }
  it { expect(subject).to validate_uniqueness_of :name }

  describe 'used_in_guests' do
    it 'should get all guests that has Services using this Certificate' do
      expect(CloudModel::Guest).to receive(:where).with('services.deploy_solr_image_id' => subject.id).and_return 'LIST OF GUESTS'
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
      allow(subject).to receive(:used_in_guests) { guests }

      expect(subject.used_in_guests_by_hosts).to eq({
        'host1' => [guests[0], guests[2]],
        'host2' => [guests[1]],
      })
    end
  end

  describe 'services' do
    it 'should list all services using SolrImage' do
      guest1 = double CloudModel::Guest
      guest2 = double CloudModel::Guest
      allow(subject).to receive(:used_in_guests).and_return [guest1, guest2]

      service1 = double CloudModel::Services::Solr
      service2 = double CloudModel::Services::Solr

      services1 = double
      services2 = double
      allow(guest1).to receive(:services).and_return(services1)
      allow(guest2).to receive(:services).and_return(services2)
      allow(services1).to receive(:where).with(deploy_solr_image_id: subject.id).and_return [service1]
      allow(services2).to receive(:where).with(deploy_solr_image_id: subject.id).and_return [service2]

      expect(subject.services).to eq [service1, service2]
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

  describe 'solr_mirror' do
    it 'should find SolrMirror for set solr_version' do
      solr_mirror = double CloudModel::SolrMirror
      subject.solr_version = '8.5.0'

      expect(CloudModel::SolrMirror).to receive(:find_by).with(version: '8.5.0').and_return solr_mirror

      expect(subject.solr_mirror).to eq solr_mirror
    end
  end

  describe 'build_path' do
    it 'should build in CloudModel data_directory' do
      allow(CloudModel.config).to receive(:data_directory).and_return Pathname.new '/my_home/rails_project/data'

      expect(subject.build_path).to eq "/my_home/rails_project/data/build/solr_images/#{subject.id}"
    end
  end

  describe '#build_state_id_for' do
    CloudModel::SolrImage.enum_fields[:build_state][:values].each do |k,v|
      it "should map #{v} to id #{k}" do
        expect(CloudModel::SolrImage.build_state_id_for v).to eq k
      end
    end
  end

  describe 'worker' do
    it 'should return worker for SolrImage' do
      worker = double CloudModel::Workers::SolrImageWorker, build: true
      expect(CloudModel::Workers::SolrImageWorker).to receive(:new).with(subject).and_return worker
      expect(subject.worker).to eq worker
    end
  end

  describe '#buildable_build_states' do
    it 'should return buildable states' do
      expect(CloudModel::SolrImage.buildable_build_states).to eq [:finished, :failed, :not_started]
    end
  end

  describe '#buildable_build_state_ids' do
    it 'should return buildable states ids' do
      expect(CloudModel::SolrImage.buildable_build_state_ids).to eq [240, 241, 255]
    end
  end

  describe 'buildable?' do
    it 'should be true if current build state is buildable' do
      subject.build_state = :finished
      expect(subject.buildable?).to eq true
    end

    it 'should be false if current build state is not buildable' do
      subject.build_state = :pending
      expect(subject.buildable?).to eq false
    end
  end

  describe '#buildable' do
    it 'should return all buildable SolrImages' do
      scoped = double
      buildable_solr_images = double
      allow(CloudModel::SolrImage).to receive(:scoped).and_return scoped
      allow(CloudModel::SolrImage).to receive(:buildable_build_state_ids).and_return [240, 241, 255]
      expect(scoped).to receive(:where).with(:build_state_id.in => [240, 241, 255]).and_return buildable_solr_images
      expect(CloudModel::SolrImage.buildable).to eq buildable_solr_images
    end
  end

  describe 'build' do
    it 'should enqueue job to build SolrImage' do
      job = double "ActiveJob"
      expect(CloudModel::SolrImageJobs::BuildJob).to receive(:perform_later).with(subject.id).and_return job
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build).to eq job
    end

    it 'should set build_state to :pending' do
      job = double "ActiveJob"
      expect(CloudModel::SolrImageJobs::BuildJob).to receive(:perform_later).with(subject.id).and_return job
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build).to eq job

      expect(subject.build_state).to eq :pending
    end

    it 'should return false and not enqueue job if not buildable' do
      expect(CloudModel::SolrImageJobs::BuildJob).not_to receive(:perform_later)
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build).to eq false
      expect(subject.build_state).to eq :not_started
    end

    it 'should allow to force build if not buildable' do
      job = double "ActiveJob"
      expect(CloudModel::SolrImageJobs::BuildJob).to receive(:perform_later).with(subject.id).and_return job
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build force:true).to eq job
      expect(subject.build_state).to eq :pending
    end

    it 'should mark template build as failed if enqueue job raises an error' do
      expect(CloudModel::SolrImageJobs::BuildJob).to receive(:perform_later).and_raise 'Rake failed to call'

      expect(subject.build).to eq false
      expect(subject.build_state).to eq :failed
      expect(subject.build_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
  end

  describe 'build!' do
    it 'should call worker to build SolrImage' do
      worker = double CloudModel::Workers::SolrImageWorker, build: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build!).to eq true
      expect(subject.build_state).to eq :pending
    end

    it 'should return false and not run worker if not buildable' do
      expect(subject).not_to receive(:worker)
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build!).to eq false
      expect(subject.build_state).to eq :not_started
    end

    it 'should allow to force build if not buildable' do
      worker = double CloudModel::Workers::SolrImageWorker, build: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build! force:true).to eq true
    end
  end
end