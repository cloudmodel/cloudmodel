# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::ForgejoRunnerComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  it 'should be named by release' do
    expect(subject.base_name).to eq 'forgejo_runner'
    expect(subject.name).to eq :forgejo_runner
    subject.version = '13.2.1'
    expect(subject.name).to eq :"forgejo_runner@13.2.1"
    expect(subject.human_name).to eq 'ForgejoRunner 13.2.1'
  end

  it 'should resolve from the versioned symbol' do
    component = CloudModel::Components::BaseComponent.from_sym :"forgejo_runner@13.2.1"
    expect(component).to be_a CloudModel::Components::ForgejoRunnerComponent
    expect(component.version).to eq '13.2.1'
  end

  describe 'worker' do
    it 'should return the component worker' do
      host = double CloudModel::Host
      template = double
      expect(CloudModel::Workers::Components::ForgejoRunnerComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return :worker
      expect(subject.worker template, host).to eq :worker
    end
  end
end
