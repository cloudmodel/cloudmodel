# encoding: UTF-8

require 'spec_helper'

describe CloudModel::WebImage do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:git_server).of_type String }
  it { expect(subject).to have_field(:git_repo).of_type String }
  it { expect(subject).to have_field(:git_branch).of_type(String).with_default_value_of 'master' }
  it { expect(subject).to have_field(:git_commit).of_type String }
  it { expect(subject).to have_field(:has_assets).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:has_mongodb).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:has_redis).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:additional_components).of_type(Array).with_default_value_of [] }

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


  it { expect(subject).to belong_to(:file).of_type Mongoid::GridFS::Fs::File }

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

  describe 'build_path' do
    it 'should build in CloudModel data_directory' do
      allow(CloudModel.config).to receive(:data_directory).and_return Pathname.new '/my_home/rails_project/data'

      expect(subject.build_path).to eq "/my_home/rails_project/data/build/web_images/#{subject.id}"
    end
  end

  describe 'build_gem_home' do
    it 'should give path to gem_home of deployed WebImage' do
      allow(subject).to receive(:build_path).and_return '/tmp/build/master'
      allow(Bundler).to receive(:ruby_scope).and_return 'ruby/4.2.0'

      expect(subject.build_gem_home).to eq '/tmp/build/master/shared/bundle/ruby/4.2.0'
    end

  end

  describe 'build_gemfile' do
    it 'should give path to Gemfile of deployed WebImage' do
      allow(subject).to receive(:build_path).and_return '/tmp/build/master'
      expect(subject.build_gemfile).to eq '/tmp/build/master/current/Gemfile'
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
    it 'should return worker for WebImage' do
      worker = double CloudModel::Workers::WebImageWorker, build: true
      expect(CloudModel::Workers::WebImageWorker).to receive(:new).with(subject).and_return worker
      expect(subject.worker).to eq worker
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
    it 'should call rake to build WebImage' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:web_image:build', web_image_id: subject.id).and_return true
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build).to eq true
    end

    it 'should set build_state to :pending' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:web_image:build', web_image_id: subject.id).and_return true
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build).to eq true

      expect(subject.build_state).to eq :pending
    end

    it 'should return false and not run rake if not buildable' do
      expect(CloudModel).not_to receive(:call_rake)
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build).to eq false
      expect(subject.build_state).to eq :not_started
    end

    it 'should allow to force build if not buildable' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:web_image:build', web_image_id: subject.id).and_return true
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build force:true).to eq true
      expect(subject.build_state).to eq :pending
    end

    it 'should mark template build as failed if rake is not callable and return false' do
      allow(CloudModel).to receive(:call_rake).and_raise 'Rake failed to call'

      expect(subject.build).to eq false
      expect(subject.build_state).to eq :failed
      expect(subject.build_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
  end

  describe 'build!' do
    it 'should call worker to build WebImage' do
      worker = double CloudModel::Workers::WebImageWorker, build: true
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
      worker = double CloudModel::Workers::WebImageWorker, build: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build! force:true).to eq true
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
    it 'should call rake to redeploy WebImage' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:web_image:redeploy', web_image_id: subject.id).and_return true
      allow(subject).to receive(:redeployable?).and_return true

      expect(subject.redeploy).to eq true
    end

    it 'should set redeploy_state to :pending' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:web_image:redeploy', web_image_id: subject.id).and_return true
      allow(subject).to receive(:redeployable?).and_return true

      expect(subject.redeploy).to eq true

      expect(subject.redeploy_state).to eq :pending
    end

    it 'should mark services as pending if redeployble' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:web_image:redeploy', web_image_id: subject.id).and_return true
      allow(subject).to receive(:redeployable?).and_return true

      service1 = double CloudModel::Services::Nginx, redeployable?: false
      service2 = double CloudModel::Services::Nginx, redeployable?: true
      allow(subject).to receive(:services).and_return [service1, service2]
      expect(service1).not_to receive :update_attribute
      expect(service2).to receive(:update_attribute).with(:redeploy_web_image_state, :pending)

      expect(subject.redeploy).to eq true
      expect(subject.redeploy_state).to eq :pending
    end

    it 'should return false and not run rake if not redeployable' do
      expect(CloudModel).not_to receive(:call_rake)
      allow(subject).to receive(:redeployable?).and_return false

      expect(subject.redeploy).to eq false
      expect(subject.redeploy_state).to eq :not_started
    end

    it 'should allow to force redeploy if not redeployable' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:web_image:redeploy', web_image_id: subject.id).and_return true
      allow(subject).to receive(:redeployable?).and_return false

      expect(subject.redeploy force:true).to eq true
      expect(subject.redeploy_state).to eq :pending
    end

    it 'should mark template build as failed if rake is not callable and return false' do
      allow(CloudModel).to receive(:call_rake).and_raise 'Rake failed to call'

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