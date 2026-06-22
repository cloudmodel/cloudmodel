# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::JitsiComponent do
  it { expect(subject).to be_a CloudModel::Components::JitsiComponent }

  describe 'base_name' do
    it 'should return "jitsi"' do
      expect(subject.base_name).to eq 'jitsi'
    end
  end

  describe 'name' do
    it 'should return :jitsi' do
      expect(subject.name).to eq :jitsi
    end

    it 'should return :jitsi even if version is set' do
      subject.version = "42.23"
      expect(subject.name).to eq :jitsi
    end
  end

  describe 'human_name' do
    it 'should return "Jitsi"' do
      expect(subject.human_name).to eq "Jitsi"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::JitsiComponentWorker

      expect(CloudModel::Workers::Components::JitsiComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require nginx and Java 11' do
      expect(subject.requirements).to eq [:nginx, :'java@11']
    end
  end
end
