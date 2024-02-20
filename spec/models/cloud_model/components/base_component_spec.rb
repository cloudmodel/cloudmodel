# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::BaseComponent do
  describe 'initialize' do
    it 'should accept version option' do
      object = CloudModel::Components::BaseComponent.new version: '42'
      expect(object.version).to eq '42'
    end
  end

  describe '.from_sym' do
    it 'should return instance of component' do
      expect(CloudModel::Components::NginxComponent).to receive(:new).and_return subject
      expect(CloudModel::Components::BaseComponent.from_sym :nginx).to eq subject
    end

    it 'should return instance of component with set version' do
      expect(CloudModel::Components::MongodbComponent).to receive(:new).with(version: '6.4').and_return subject
      expect(CloudModel::Components::BaseComponent.from_sym :'mongodb@6.4').to eq subject
    end

    it 'should raise error if component does not match any class' do
      expect{CloudModel::Components::BaseComponent.from_sym :hal9000}.to raise_error 'uninitialized constant CloudModel::Components::Hal9000Component'
    end
  end

  describe 'base_name' do
    it 'should return "base"' do
      expect(subject.base_name).to eq 'base'
    end

    it 'should return "base" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'base'
    end
  end

  describe 'name' do
    it 'should return :base' do
      expect(subject.name).to eq :base
    end

    it 'should return :base@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'base@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "Base"' do
      expect(subject.human_name).to eq "Base"
    end

    it 'should return "Base 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "Base 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::BaseComponentWorker

      expect(CloudModel::Workers::Components::BaseComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end