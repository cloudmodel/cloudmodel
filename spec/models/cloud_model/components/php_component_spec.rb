# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::PhpComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "php"' do
      expect(subject.base_name).to eq 'php'
    end

    it 'should return "php" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'php'
    end
  end

  describe 'name' do
    it 'should return :php' do
      expect(subject.name).to eq :php
    end

    it 'should return :php@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'php@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "PHP"' do
      expect(subject.human_name).to eq "PHP"
    end

    it 'should return "PHP 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "PHP 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::PhpComponentWorker

      expect(CloudModel::Workers::Components::PhpComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end