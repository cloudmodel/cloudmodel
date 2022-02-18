# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::Java8Component do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "java8"' do
      expect(subject.base_name).to eq 'java8'
    end
  end

  describe 'name' do
    it 'should return :java8' do
      expect(subject.name).to eq :java8
    end
  end

  describe 'human_name' do
    it 'should return "Java 8"' do
      expect(subject.human_name).to eq "Java 8"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      worker_class = double CloudModel::Workers::Components::Java8ComponentWorker

      expect(CloudModel::Workers::Components::Java8ComponentWorker).to receive(:new).with(host, component: subject).and_return worker_class
      expect(subject.worker host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end