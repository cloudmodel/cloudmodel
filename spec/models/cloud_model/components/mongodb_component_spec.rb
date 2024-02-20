# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::MongodbComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "mongodb"' do
      expect(subject.base_name).to eq 'mongodb'
    end

    it 'should return "mongodb" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'mongodb'
    end
  end

  describe 'name' do
    it 'should return :mongodb' do
      expect(subject.name).to eq :mongodb
    end

    it 'should return :mongodb@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'mongodb@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "MongoDB"' do
      expect(subject.human_name).to eq "MongoDB"
    end

    it 'should return "MongoDB 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "MongoDB 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::MongodbComponentWorker

      expect(CloudModel::Workers::Components::MongodbComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end