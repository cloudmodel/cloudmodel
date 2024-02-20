# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::TomcatComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "tomcat"' do
      expect(subject.base_name).to eq 'tomcat'
    end

    it 'should return "tomcat" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'tomcat'
    end
  end

  describe 'name' do
    it 'should return :tomcat' do
      expect(subject.name).to eq :tomcat
    end

    it 'should return :tomcat@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'tomcat@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "Tomcat"' do
      expect(subject.human_name).to eq "Tomcat"
    end

    it 'should return "Tomcat 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "Tomcat 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::TomcatComponentWorker

      expect(CloudModel::Workers::Components::TomcatComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require :java' do
      expect(subject.requirements).to eq [:java]
    end
  end
end