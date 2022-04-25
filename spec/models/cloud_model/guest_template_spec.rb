# encoding: UTF-8

require 'spec_helper'

describe CloudModel::GuestTemplate do
  it { expect(subject).to have_timestamps }

  it { expect(subject).to have_field(:os_version).of_type(String).with_default_value_of "ubuntu-#{CloudModel.config.ubuntu_version}" }
  it { expect(subject).to have_field(:arch).of_type String }

  it { expect(subject).to have_enum(:build_state).with_values(
    0x00 => :pending,
    0x01 => :running,
    0x05 => :packaging,
    0x10 => :downloading,
    0xf0 => :finished,
    0xf1 => :failed,
    0xff => :not_started
  ).with_default_value_of(:not_started) }
  it { expect(subject).to have_field(:build_last_issue).of_type(String) }

  let(:host) { double CloudModel::Host, id: BSON::ObjectId.new, arch: 'MOS6502'}
  let(:guest_template_type) { double CloudModel::GuestTemplateType, id: BSON::ObjectId.new }

  describe '#buildable_build_states' do
    it 'should return buildable states' do
      expect(CloudModel::GuestTemplate.buildable_build_states).to eq [:finished, :failed, :not_started]
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

  describe '#latest_created_at' do
    it 'should get creation of latest successfully build template' do
      scoped = double
      collection = double
      created_at = Time.now - 10.days
      allow(CloudModel::GuestCoreTemplate).to receive(:scoped).and_return scoped
      allow(scoped).to receive(:where).with(build_state_id: 0xf0).and_return collection
      expect(collection).to receive(:max).with(:created_at).and_return created_at

      expect(CloudModel::GuestCoreTemplate.latest_created_at).to eq created_at
    end

    it 'should get creation of latest successfully build template on scope' do
      collection = double
      created_at = Time.now - 10.days
      scoped = CloudModel::GuestCoreTemplate.where(arch: 'mos6502')

      allow(scoped).to receive(:where).with(build_state_id: 0xf0).and_return collection
      expect(collection).to receive(:max).with(:created_at).and_return created_at

      expect(scoped.latest_created_at).to eq created_at
    end
  end

  describe 'worker' do
    it 'should return worker for GuestTemplate' do
      worker = double CloudModel::Workers::GuestTemplateWorker, build_template: true
      expect(CloudModel::Workers::GuestTemplateWorker).to receive(:new).with(host).and_return worker
      expect(subject.worker host).to eq worker
    end
  end

  describe 'build' do
    it 'should call rake to build GuestTemplate' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:guest_template:build', host_id: host.id, template_id: subject.id).and_return true
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build host).to eq true
    end

    it 'should set build_state to :pending' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:guest_template:build', host_id: host.id, template_id: subject.id).and_return true
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build host).to eq true

      expect(subject.build_state).to eq :pending
    end

    it 'should return false and not run rake if not buildable' do
      expect(CloudModel).not_to receive(:call_rake)
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build host).to eq false
      expect(subject.build_state).to eq :not_started
    end

    it 'should allow to force build if not buildable' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:guest_template:build', host_id: host.id, template_id: subject.id).and_return true
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build host, force:true).to eq true
      expect(subject.build_state).to eq :pending
    end

    it 'should mark template build as failed if rake is not callable and return false' do
      allow(CloudModel).to receive(:call_rake).and_raise 'Rake failed to call'

      expect(subject.build host).to eq false
      expect(subject.build_state).to eq :failed
      expect(subject.build_last_issue).to eq 'Unable to enqueue job! Try again later.'
    end
  end

  describe 'build!' do
    it 'should call worker to build GuestTemplate' do
      worker = double CloudModel::Workers::GuestTemplateWorker, build_template: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:buildable?).and_return true

      expect(subject.build! host).to eq true
      expect(subject.build_state).to eq :pending
    end

    it 'should return false and not run worker if not buildable' do
      expect(subject).not_to receive(:worker)
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build! host).to eq false
      expect(subject.build_state).to eq :not_started
    end

    it 'should allow to force build if not buildable' do
      worker = double CloudModel::Workers::GuestTemplateWorker, build_template: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:buildable?).and_return false

      expect(subject.build! host, force:true).to eq true
    end

    it 'should pass template type and options to worker build_template' do
      subject.template_type_id = guest_template_type.id

      worker = double CloudModel::Workers::GuestTemplateWorker, build_template: true
      allow(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:buildable?).and_return true

      expect(worker).to receive(:build_template).with(subject, debug: true).and_return true

      expect(subject.build! host, debug: true).to eq true
    end
  end

  describe 'lxd_arch' do
    it 'should map amd64 to x86_64' do
      subject.arch = 'amd64'
      expect(subject.lxd_arch).to eq 'x86_64'
    end

    it 'should pass arch if not amd64' do
      subject.arch = 'arm64'
      expect(subject.lxd_arch).to eq 'arm64'
    end
  end

  describe 'name' do
    it 'should concatinate template type name and created date' do
      allow(subject.template_type).to receive(:name).and_return "Some Template Type"
      allow(subject).to receive(:created_at).and_return Time.parse('30.03.2020 13:37:42.23')

      expect(subject.name).to eq "Some Template Type (2020-03-30 13:37:42)"
    end

    it 'should allow to give name on not saved templates' do
      allow(subject.template_type).to receive(:name).and_return "Some Template Type"
      allow(subject).to receive(:created_at).and_return nil

      expect(subject.name).to eq "Some Template Type (not saved)"
    end
  end

  describe 'lxd_image_metadata_tarball' do
    it 'should return path to templates tarball' do
      subject.template_type_id = guest_template_type.id
      expect(subject.lxd_image_metadata_tarball).to eq "/cloud/templates/#{guest_template_type.id}/#{subject.id}.lxd.tar.gz"
    end
  end

  describe 'lxd_alias' do
    it 'should return lxd alias for template' do
      subject.template_type_id = guest_template_type.id
      expect(subject.lxd_alias).to eq "#{guest_template_type.id}/#{subject.id}"
    end
  end

  describe 'tarball' do
    it 'should return path to templates tarball' do
      subject.template_type_id = guest_template_type.id
      expect(subject.tarball).to eq "/cloud/templates/#{guest_template_type.id}/#{subject.id}.tar.gz"
    end
  end
end