# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::CollaboraComponent do
  it { expect(subject).to be_a CloudModel::Components::CollaboraComponent }

  describe 'base_name' do
    it 'should return "collabora"' do
      expect(subject.base_name).to eq 'collabora'
    end

    it 'should return "collabora" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'collabora'
    end
  end

  describe 'name' do
    it 'should return :collabora' do
      expect(subject.name).to eq :collabora
    end

    it 'should return :collabora@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'collabora@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "Collabora"' do
      expect(subject.human_name).to eq "Collabora"
    end

    it 'should return "Collabora 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "Collabora 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::CollaboraComponentWorker

      expect(CloudModel::Workers::Components::CollaboraComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require no additional components' do
      expect(subject.requirements).to eq []
    end
  end
end
