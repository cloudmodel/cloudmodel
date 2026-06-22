# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::ForgejoComponent do
  it { expect(subject).to be_a CloudModel::Components::ForgejoComponent }

  describe 'base_name' do
    it 'should return "forgejo"' do
      expect(subject.base_name).to eq 'forgejo'
    end
  end

  describe 'name' do
    it 'should return :forgejo' do
      expect(subject.name).to eq :forgejo
    end

    it 'should still return :forgejo even if version is set' do
      subject.version = "42.23"
      expect(subject.name).to eq :forgejo
    end
  end

  describe 'human_name' do
    it 'should return "Forgejo"' do
      expect(subject.human_name).to eq "Forgejo"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::ForgejoComponentWorker

      expect(CloudModel::Workers::Components::ForgejoComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should have no requirements' do
      expect(subject.requirements).to eq []
    end
  end
end
