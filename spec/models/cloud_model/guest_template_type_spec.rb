# encoding: UTF-8

require 'spec_helper'

describe CloudModel::GuestTemplateType do
  it { expect(subject).to have_timestamps }

  #it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:os_version).of_type(String).with_default_value_of "ubuntu-#{CloudModel.config.ubuntu_version}" }
  it { expect(subject).to have_field(:components).of_type(Array).with_default_value_of [] }
  it { expect(subject).to have_many(:templates).of_type CloudModel::GuestTemplate}

  let(:host) { double CloudModel::Host, id: BSON::ObjectId.new, arch: 'MOS6502'}

  describe 'new_template' do
    it 'should create new template for host arch' do
      core_template = double CloudModel::GuestCoreTemplate, arch: 'MOS6502'
      template = double CloudModel::GuestTemplate
      expect(CloudModel::GuestCoreTemplate).to receive(:last_useable).with(host).and_return core_template
      allow(subject).to receive(:os_version).and_return 'basic-2.0'
      expect(subject.templates).to receive(:create).with(
        core_template: core_template,
        os_version: 'basic-2.0',
        arch: 'MOS6502'
      ).and_return template

      expect(subject.new_template host).to eq template
    end
  end

  describe 'build_new_template!' do
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

  describe '#last_useable' do
    let(:build_host) { double CloudModel::Host, name: 'build', arch: 'MOS6502' }

    before do
      allow(CloudModel::Host).to receive(:build_host).with('MOS6502').and_return build_host
    end

    it 'should get latest finished template for given host arch' do
      template = double CloudModel::GuestTemplate
      expect(subject).to receive(:finished_template).with('MOS6502').and_return template
      expect(subject.last_useable host).to eq template
    end

    it 'should return a template that is being built instead of building another one' do
      building = double CloudModel::GuestTemplate
      allow(subject).to receive(:finished_template).and_return nil
      expect(subject).to receive(:building_template).with('MOS6502').and_return building
      expect(subject).not_to receive(:new_template)

      expect(subject.last_useable host).to eq building
    end

    it 'should create, mark pending and build a new template on the build host if there is none' do
      template = double CloudModel::GuestTemplate
      allow(subject).to receive(:finished_template).and_return nil
      allow(subject).to receive(:building_template).and_return nil
      expect(subject).to receive(:new_template).with(host).and_return template
      expect(template).to receive(:update_attribute).with(:build_state, :pending).ordered
      expect(template).to receive(:build!).with(build_host, { force: true }).ordered
      expect(template).to receive(:reload).and_return template

      expect(subject.last_useable host).to eq template
    end

    it 'should build exactly one template when several threads ask at once' do
      created = []
      lock = Mutex.new
      allow(subject).to receive(:finished_template).and_return nil
      allow(subject).to receive(:building_template) { lock.synchronize { created.first } }
      allow(subject).to receive(:new_template) do
        t = double('template', update_attribute: true, reload: nil)
        allow(t).to receive(:build!) { sleep 0.05 }
        allow(t).to receive(:reload).and_return t
        lock.synchronize { created << t }
        t
      end

      results = 5.times.map { Thread.new { subject.last_useable host } }.map(&:value)
      expect(created.size).to eq 1
      expect(results.uniq).to eq created
    end

    it 'should build a new one with force_rebuild even if one is finished' do
      template = double CloudModel::GuestTemplate, update_attribute: true
      allow(subject).to receive(:finished_template).and_return double('old')
      expect(subject).to receive(:new_template).and_return template
      expect(template).to receive(:build!).with(build_host, { force_rebuild: true, force: true })
      allow(template).to receive(:reload).and_return template

      expect(subject.last_useable host, force_rebuild: true).to eq template
    end
  end

  describe 'componant_names' do
    it 'should get human readable names if possible' do
      subject.components = [:nginx, :'mongodb@5.0', :redis]
      expect(subject.componant_names).to eq ['NGINX', 'MongoDB 5.0', 'Redis']
    end

    it 'should fallback to generic name if not found' do
      subject.components = [:xml, :hal9000, :'tron_mcp@42']
      expect(subject.componant_names).to eq ['XML', 'Hal9000', 'TronMcp@42']
    end
  end

  describe 'name' do
    it 'should handle GuestTemplateType without components' do
      subject.os_version = 'basic-2.0'
      expect(subject.name).to eq 'basic-2.0 without components'
    end

    it 'should concatinate components to name' do
      subject.os_version = 'basic-7.0'
      subject.components = [:nginx, :'mongodb@5.0', :redis]
      expect(subject.name).to eq 'basic-7.0 with NGINX, MongoDB 5.0, Redis'
    end
  end
end