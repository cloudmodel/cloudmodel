# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::JavaComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "java"' do
      expect(subject.base_name).to eq 'java'
    end

    it 'should return "java" if version is set' do
      subject.version = "23"
      expect(subject.base_name).to eq 'java'
    end
  end

  describe 'name' do
    it 'should return :java' do
      expect(subject.name).to eq :java
    end

    it 'should return :java@23 if version is set to 23' do
      subject.version = "23"
      expect(subject.name).to eq :'java@23'
    end
  end

  describe 'human_name' do
    it 'should return "Java"' do
      expect(subject.human_name).to eq "Java"
    end

    it 'should return "Java 23" if version is set to 23' do
      subject.version = "23"
      expect(subject.human_name).to eq "Java 23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::JavaComponentWorker

      expect(CloudModel::Workers::Components::JavaComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end