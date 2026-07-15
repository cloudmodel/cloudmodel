# encoding: UTF-8

require 'spec_helper'

describe CloudModel::WebImage do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:git_server).of_type String }
  it { expect(subject).to have_field(:git_repo).of_type String }
  it { expect(subject).to have_field(:git_branch).of_type(String).with_default_value_of 'master' }
  it { expect(subject).to have_field(:git_commit).of_type String }
  it { expect(subject).to have_field(:master_key).of_type(String).with_default_value_of nil }
  it { expect(subject).to have_field(:has_assets).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:has_mongodb).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:has_redis).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:additional_components).of_type(Array).with_default_value_of [] }
  it { expect(subject).to have_field(:mongodb_backup_exclude_collection_prefixes).of_type(Array).with_default_value_of [] }

  describe 'mongodb_backup_exclude_collection_prefixes=' do
    it 'splits a whitespace/comma separated string into an array' do
      subject.mongodb_backup_exclude_collection_prefixes = 'fs, search_journal  index_collection'
      expect(subject.mongodb_backup_exclude_collection_prefixes).to eq %w(fs search_journal index_collection)
    end

    it 'accepts an array and drops blanks' do
      subject.mongodb_backup_exclude_collection_prefixes = ['fs', '', ' search_journal ']
      expect(subject.mongodb_backup_exclude_collection_prefixes).to eq %w(fs search_journal)
    end
  end

  it { expect(subject).to have_enum(:build_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0x02 => :checking_out,
    0x03 => :bundling,
    0x04 => :building_assets,
    0x05 => :packaging,
    0x06 => :storing,
    0xf0 => :finished,
    0xf1 => :failed,
    0xff => :not_started
  ).with_default_value_of(:not_started) }
  it { expect(subject).to have_field(:build_last_issue).of_type(String) }

  it { expect(subject).to have_enum(:redeploy_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0xf0 => :finished,
    0xf1 => :failed,
    0xff => :not_started
  ).with_default_value_of(:not_started) }
  it { expect(subject).to have_field(:redeploy_last_issue).of_type(String) }


  it { expect(subject).to have_field(:artifact_sizes).of_type(Hash).with_default_value_of({}) }

  it { expect(subject).to validate_presence_of :name }
  it { expect(subject).to validate_presence_of :git_server }
  it { expect(subject).to validate_presence_of :git_repo }
  it { expect(subject).to validate_presence_of :git_branch }
  it { expect(subject).to validate_uniqueness_of :name }

  describe 'used_in_guests' do
    it 'should get all guests that has Services using this Certificate' do
      expect(CloudModel::Guest).to receive(:where).with('services.deploy_web_image_id' => subject.id).and_return 'LIST OF GUESTS'
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
    it 'should list all services using WebImage' do
      guest1 = double CloudModel::Guest
      guest2 = double CloudModel::Guest
      allow(subject).to receive(:used_in_guests).and_return [guest1, guest2]

      service1 = double CloudModel::Services::Nginx
      service2 = double CloudModel::Services::Nginx

      services1 = double
      services2 = double
      allow(guest1).to receive(:services).and_return(services1)
      allow(guest2).to receive(:services).and_return(services2)
      allow(services1).to receive(:where).with(deploy_web_image_id: subject.id).and_return [service1]
      allow(services2).to receive(:where).with(deploy_web_image_id: subject.id).and_return [service2]

      expect(subject.services).to eq [service1, service2]
    end
  end

  describe 'total_artifact_usage' do
    it 'should sum the recorded artifact sizes' do
      subject.artifact_sizes = {'tpl-MOS6502' => 1000, 'tpl-MC68000' => 2000}
      expect(subject.total_artifact_usage).to eq 3000
    end

    it 'should be zero when nothing was built' do
      subject.artifact_sizes = {}
      expect(subject.total_artifact_usage).to eq 0
    end
  end

  describe 'build_dataset / build_mountpoint / build_snapshot' do
    before do
      allow(CloudModel.config).to receive(:build_dataset).and_return 'guests/build'
    end

    it 'keys the app dataset by web image and arch (decoupled from the template)' do
      expect(subject.build_dataset('MOS6502')).to eq "guests/build/web/#{subject.id}/MOS6502"
    end

    it 'mounts under /cloud/build/web' do
      expect(subject.build_mountpoint('MOS6502')).to eq "/cloud/build/web/#{subject.id}/MOS6502"
    end

    it 'points the current version snapshot at the app dataset' do
      subject.artifact_versions = {'MOS6502' => '20260101000000'}
      expect(subject.build_snapshot('MOS6502')).to eq "guests/build/web/#{subject.id}/MOS6502@v20260101000000"
    end

    it 'has no build snapshot before the first build' do
      expect(subject.build_snapshot('MOS6502')).to be_nil
    end

    it 'web_volume_ready? checks the current version snapshot on the host' do
      subject.artifact_versions = {'MOS6502' => '20260101000000'}
      host = double CloudModel::Host
      expect(host).to receive(:exec).with(/zfs list -t snapshot .*\/MOS6502@v20260101000000/).and_return [true, 'x']
      expect(subject.web_volume_ready?(host, 'MOS6502')).to be_truthy
    end
  end

  describe 'build_path' do
    it 'should build in CloudModel data_directory' do
      allow(CloudModel.config).to receive(:data_directory).and_return Pathname.new '/my_home/rails_project/data'

      expect(subject.build_path).to eq "/my_home/rails_project/data/build/web_images/#{subject.id}"
    end
  end

  describe '#build_state_id_for' do
    CloudModel::WebImage.enum_fields[:build_state][:values].each do |k,v|
      it "should map #{v} to id #{k}" do
        expect(CloudModel::WebImage.build_state_id_for v).to eq k
      end
    end
  end

  describe 'worker' do
    it 'should return worker for WebImage on the given build host' do
      host = double CloudModel::Host
      worker = double CloudModel::Workers::WebImageWorker
      expect(CloudModel::Workers::WebImageWorker).to receive(:new).with(host, subject).and_return worker
      expect(subject.worker(host)).to eq worker
    end
  end

  describe '#buildable_build_states' do
    it 'should return buildable states' do
      expect(CloudModel::WebImage.buildable_build_states).to eq [:finished, :failed, :not_started]
    end
  end

  describe '#buildable_build_state_ids' do
    it 'should return buildable states ids' do
      expect(CloudModel::WebImage.buildable_build_state_ids).to eq [240, 241, 255]
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
    it 'should return all buildable WebImages' do
      scoped = double
      buildable_web_images = double
      allow(CloudModel::WebImage).to receive(:scoped).and_return scoped
      allow(CloudModel::WebImage).to receive(:buildable_build_state_ids).and_return [240, 241, 255]
      expect(scoped).to receive(:where).with(:build_state_id.in => [240, 241, 255]).and_return buildable_web_images
      expect(CloudModel::WebImage.buildable).to eq buildable_web_images
    end
  end

  describe 'build' do
    it 'should enqueue job to build WebImage' do
      job = double "ActiveJob"
      expect(CloudModel::WebImageJobs::BuildJob).to receive(:perform_later).with(subject.id).and_return job

      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build).to eq job
    end

    it 'should set build_state to :pending' do
      job = double "ActiveJob"
      expect(CloudModel::WebImageJobs::BuildJob).to receive(:perform_later).with(subject.id).and_return job
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build).to eq job

      expect(subject.build_state).to eq :pending
    end

    it 'should return false and not enqueue job if not buildable' do
      expect(CloudModel::WebImageJobs::BuildJob).not_to receive(:perform_later)
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build).to eq false
      expect(subject.build_state).to eq :not_started
    end

    it 'should allow to force enqueue if not buildable' do
      job = double "ActiveJob"
      expect(CloudModel::WebImageJobs::BuildJob).to receive(:perform_later).with(subject.id).and_return job
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build force:true).to eq job
      expect(subject.build_state).to eq :pending
    end

    it 'should mark template build as failed if enqueue raises error' do
      expect(CloudModel::WebImageJobs::BuildJob).to receive(:perform_later).and_raise 'Rake failed to call'

      expect(subject.build).to eq false
      expect(subject.build_state).to eq :failed
      expect(subject.build_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
  end

  describe 'build!' do
    let(:host) { double CloudModel::Host }
    let(:worker) { double CloudModel::Workers::WebImageWorker }

    before do
      allow(subject).to receive(:build_targets).and_return ['MOS6502']
      allow(CloudModel::Host).to receive(:build_host).with('MOS6502').and_return host
      allow(subject).to receive(:worker).with(host).and_return worker
    end

    it 'should build every arch target on its arch build host' do
      allow(subject).to receive(:buildable?).and_return true
      expect(worker).to receive(:build_app_volume).with('MOS6502', {})

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
      allow(subject).to receive(:buildable?).and_return false
      expect(worker).to receive(:build_app_volume).with('MOS6502', {force: true})

      expect(subject.build! force: true).to eq true
    end

    it 'should fail when no build host is configured for a target arch' do
      allow(subject).to receive(:buildable?).and_return true
      allow(CloudModel::Host).to receive(:build_host).with('MOS6502').and_return nil

      expect(subject.build!).to eq false
      expect(subject.build_state).to eq :failed
    end
  end

  describe '#redeployable_redeploy_states' do
    it 'should return redeployable states' do
      expect(CloudModel::WebImage.redeployable_redeploy_states).to eq [:finished, :failed, :not_started]
    end
  end

  describe 'redeployable?' do
    it 'should be true if current redeploy state is redeployable' do
      subject.redeploy_state = :finished
      expect(subject.redeployable?).to eq true
    end

    it 'should be false if current redeploy state is not redeployable' do
      subject.redeploy_state = :pending
      expect(subject.redeployable?).to eq false
    end
  end

  describe 'redeploy' do
    it 'should enqueue job to redeploy WebImage' do
      job = double "ActiveJob"
      expect(CloudModel::WebImageJobs::RedeployJob).to receive(:perform_later).with(subject.id).and_return job

      allow(subject).to receive(:redeployable?).and_return true

      expect(subject.redeploy).to eq job
    end

    it 'should set redeploy_state to :pending' do
      job = double "ActiveJob"
      expect(CloudModel::WebImageJobs::RedeployJob).to receive(:perform_later).with(subject.id).and_return job
      allow(subject).to receive(:redeployable?).and_return true

      expect(subject.redeploy).to eq job

      expect(subject.redeploy_state).to eq :pending
    end

    it 'should mark services as pending if redeployble' do
      job = double "ActiveJob"
      expect(CloudModel::WebImageJobs::RedeployJob).to receive(:perform_later).with(subject.id).and_return job
      allow(subject).to receive(:redeployable?).and_return true

      service1 = double CloudModel::Services::Nginx, redeployable?: false
      service2 = double CloudModel::Services::Nginx, redeployable?: true
      allow(subject).to receive(:services).and_return [service1, service2]
      expect(service1).not_to receive :update_attribute
      expect(service2).to receive(:update_attribute).with(:redeploy_web_image_state, :pending)

      expect(subject.redeploy).to eq job
      expect(subject.redeploy_state).to eq :pending
    end

    it 'should return false and not enqueue job if not redeployable' do
      expect(CloudModel::WebImageJobs::RedeployJob).not_to receive(:perform_later)
      allow(subject).to receive(:redeployable?).and_return false

      expect(subject.redeploy).to eq false
      expect(subject.redeploy_state).to eq :not_started
    end

    it 'should allow to force enqueue redeploy if not redeployable' do
      job = double "ActiveJob"
      expect(CloudModel::WebImageJobs::RedeployJob).to receive(:perform_later).with(subject.id).and_return job
      allow(subject).to receive(:redeployable?).and_return false

      expect(subject.redeploy force:true).to eq job
      expect(subject.redeploy_state).to eq :pending
    end

    it 'should mark template build as failed if enqueue job raises error' do
      expect(CloudModel::WebImageJobs::RedeployJob).to receive(:perform_later).and_raise 'Rake failed to call'

      expect(subject.redeploy).to eq false
      expect(subject.redeploy_state).to eq :failed
      expect(subject.redeploy_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
  end

  describe 'redeploy!' do
    it 'should call worker to redeploy WebImage' do
      worker = double CloudModel::Workers::WebImageWorker, redeploy: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:redeployable?).and_return true

      expect(subject.redeploy!).to eq true
      expect(subject.redeploy_state).to eq :pending
    end

    it 'should mark services as pending if redeployble' do
      worker = double CloudModel::Workers::WebImageWorker, redeploy: true
      service1 = double CloudModel::Services::Nginx, redeployable?: false
      service2 = double CloudModel::Services::Nginx, redeployable?: true

      allow(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:redeployable?).and_return true
      allow(subject).to receive(:services).and_return [service1, service2]
      expect(service1).not_to receive :redeploy_web_image_state=
      expect(service2).to receive(:redeploy_web_image_state=).with( :pending)

      expect(subject.redeploy!).to eq true
      expect(subject.redeploy_state).to eq :pending
    end

    it 'should return false and not run worker if not redeployable' do
      expect(subject).not_to receive(:worker)
      allow(subject).to receive(:redeployable?).and_return false

      expect(subject.redeploy!).to eq false
      expect(subject.redeploy_state).to eq :not_started
    end

    it 'should allow to force redeploy if not redeployable' do
      worker = double CloudModel::Workers::WebImageWorker, redeploy: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:redeployable?).and_return false

      expect(subject.redeploy! force:true).to eq true
    end
  end
end