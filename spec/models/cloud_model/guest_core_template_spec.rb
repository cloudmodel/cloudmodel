# encoding: UTF-8

require 'spec_helper'

describe CloudModel::GuestCoreTemplate do
  it { expect(subject).to have_timestamps }  
    
  it { expect(subject).to have_field(:os_version).of_type String }
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
  
  context '#buildable_build_states' do
    it 'should return buildable states' do
      expect(CloudModel::GuestCoreTemplate.buildable_build_states).to eq [:finished, :failed, :not_started]
    end
  end
  
  context 'buildable?' do
    it 'should be true if current build state is buildable' do
      subject.build_state = :finished
      expect(subject.buildable?).to eq true
    end
    
    it 'should be false if current build state is not buildable' do
      subject.build_state = :pending
      expect(subject.buildable?).to eq false
    end
  end
  
  context '#latest_created_at' do
    it 'should get creation of latest successfully build template' do
      scoped = double
      collection = double
      created_at = Time.now - 10.days
      allow(CloudModel::GuestCoreTemplate).to receive(:scoped).and_return scoped
      allow(scoped).to receive(:where).with(build_state_id: 0xf0).and_return collection
      expect(collection).to receive(:max).with(:created_at).and_return created_at
      
      expect(CloudModel::GuestCoreTemplate.latest_created_at).to eq created_at
    end
  end
  
  context '#new_template_to_build' do
    it 'should create new GuestTemplate' do
      template = double
      expect(CloudModel::GuestCoreTemplate).to receive(:create).with(arch: 'MOS6502').and_return template
      expect(CloudModel::GuestCoreTemplate.new_template_to_build host).to eq template
    end
  end
  
  context '#build!' do
    it 'should create new template and build it' do
      template = double CloudModel::GuestCoreTemplate
      
      expect(CloudModel::GuestCoreTemplate).to receive(:new_template_to_build).with(host).and_return template
      expect(template).to receive(:build!).with(host, {})
      
      CloudModel::GuestCoreTemplate.build! host
    end
    
    it 'should pass options to build process' do
      options = double
      template = double CloudModel::GuestCoreTemplate
      
      expect(CloudModel::GuestCoreTemplate).to receive(:new_template_to_build).with(host).and_return template
      expect(template).to receive(:build!).with(host, options)
      
      CloudModel::GuestCoreTemplate.build! host, options
    end
  end
  
  context 'build' do
    it 'should call rake to build GuestCoreTemplate' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:guest_core_template:build', host_id: host.id, template_id: subject.id).and_return true
      allow(subject).to receive(:buildable?).and_return true
      
      expect(subject.build host).to eq true
    end
    
    it 'should set build_state to :pending' do
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:guest_core_template:build', host_id: host.id, template_id: subject.id).and_return true
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
      expect(CloudModel).to receive(:call_rake).with('cloudmodel:guest_core_template:build', host_id: host.id, template_id: subject.id).and_return true
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
  
  context 'worker' do
    it 'should return worker for GuestCoreTemplate' do
      worker = double CloudModel::Workers::GuestTemplateWorker, build_core_template: true
      expect(CloudModel::Workers::GuestTemplateWorker).to receive(:new).with(host).and_return worker
      expect(subject.worker host).to eq worker
    end
  end
  
  context 'build!' do
    it 'should call worker to build GuestCoreTemplate' do
      worker = double CloudModel::Workers::GuestTemplateWorker, build_core_template: true
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
      worker = double CloudModel::Workers::GuestTemplateWorker, build_core_template: true
      expect(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:buildable?).and_return false
      
      expect(subject.build! host, force:true).to eq true
    end
    
    it 'should pass template type and options to worker build_template' do
      worker = double CloudModel::Workers::GuestTemplateWorker, build_template: true
      allow(subject).to receive(:worker).and_return worker
      allow(subject).to receive(:buildable?).and_return true
      
      expect(worker).to receive(:build_core_template).with(subject, debug: true).and_return true
      
      expect(subject.build! host, debug: true).to eq true
    end
  end
  
  # def self.last_useable(host, options={})
  #   template = self.where(arch: host.arch, build_state_id: 0xf0).last
  #   unless template
  #     template = new_template_to_build host
  #     template.build_state = :pending
  #     template.build!(host, options)
  #   end
  #   template
  # end
  
  context '#last_useable' do
    it 'should get latest finished template for given host arch' do
      template = double subject.class
      expect(subject.class).to receive(:where).with(arch: 'MOS6502', build_state_id: 0xf0).and_return [template]
      expect(subject.class.last_useable host).to eq template
    end
    
    it 'should build new template if non is found' do
      template = double subject.class
      options = double
      expect(subject.class).to receive(:where).with(arch: 'MOS6502', build_state_id: 0xf0).and_return []
      expect(subject.class).to receive(:new_template_to_build).with(host).and_return template
      
      expect(template).to receive(:build_state=).with :pending
      expect(template).to receive(:build!).with(host, options)
      
      expect(subject.class.last_useable host, options).to eq template
    end
  end
  
  context 'tarball' do
    it 'should return path to templates tarball' do
      expect(subject.tarball).to eq "/cloud/templates/core/#{subject.id}.tar.gz"
    end
  end
end