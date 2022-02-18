# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::RubyComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "ruby"' do
      expect(subject.base_name).to eq 'ruby'
    end

    it 'should return "ruby" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'ruby'
    end
  end

  describe 'name' do
    it 'should return :ruby' do
      expect(subject.name).to eq :ruby
    end

    it 'should return :ruby@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'ruby@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "Ruby"' do
      expect(subject.human_name).to eq "Ruby"
    end

    it 'should return "Ruby 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "Ruby 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      worker_class = double CloudModel::Workers::Components::RubyComponentWorker

      expect(CloudModel::Workers::Components::RubyComponentWorker).to receive(:new).with(host, component: subject).and_return worker_class
      expect(subject.worker host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should be an empty Array' do
      expect(subject.requirements).to eq []
    end
  end
end