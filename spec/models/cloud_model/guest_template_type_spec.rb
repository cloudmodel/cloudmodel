# encoding: UTF-8

require 'spec_helper'

describe CloudModel::GuestTemplateType do
  it { expect(subject).to have_timestamps }  
    
  #it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:components).of_type(Array).with_default_value_of [] }
  it { expect(subject).to have_many(:templates).of_type CloudModel::GuestTemplate}
  
  let(:host) { double CloudModel::Host, id: BSON::ObjectId.new, arch: 'MOS6502'}

  context 'new_template' do
    it 'should create new template for host arch' do
      core_template = double CloudModel::GuestCoreTemplate, arch: 'MOS6502'
      template = double CloudModel::GuestTemplate
      expect(CloudModel::GuestCoreTemplate).to receive(:last_useable).with(host).and_return core_template
      expect(subject.templates).to receive(:create).with(
        core_template: core_template,
        arch: 'MOS6502'
      ).and_return template
      
      expect(subject.new_template host).to eq template
    end
  end

  context 'build_new_template!' do
    it 'should build new template' do
      template = double CloudModel::GuestTemplate
      expect(subject).to receive(:new_template).with(host).and_return template
      
      expect(template).to receive(:build_state=).with :pending
      expect(template).to receive(:build!).with(host, {})
      
      expect(subject.build_new_template! host).to eq template
    end
    
    it 'pass options to build process' do
      template = double CloudModel::GuestTemplate
      options = double
      expect(subject).to receive(:new_template).with(host).and_return template
      
      expect(template).to receive(:build_state=).with :pending
      expect(template).to receive(:build!).with(host, options)
      
      expect(subject.build_new_template! host, options).to eq template
    end
  end

  context '#last_useable' do
    it 'should get latest finished template for given host arch' do
      template = double CloudModel::GuestTemplate
      expect(subject.templates).to receive(:where).with(arch: 'MOS6502', build_state_id: 0xf0).and_return [template]
      expect(subject.last_useable host).to eq template
    end
    
    it 'should build new template if non is found' do
      template = double CloudModel::GuestTemplate
      options = double
      expect(subject.templates).to receive(:where).with(arch: 'MOS6502', build_state_id: 0xf0).and_return []
      expect(subject).to receive(:build_new_template!).with(host, options).and_return template
      
      expect(subject.last_useable host, options).to eq template
    end
  end

  context 'name' do
    it 'should handle GuestTemplateType without components' do
      expect(subject.name).to eq 'CloudModel Guest Template without components'
    end
    
    it 'should concatinate components to name' do
      subject.components = [:nginx, :mongodb, :redis]
      expect(subject.name).to eq 'CloudModel Guest Template with Nginx, Mongodb, Redis'
    end
  end
end