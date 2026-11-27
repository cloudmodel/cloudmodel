# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::PerconaServerComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'name' do
    it 'should return :percona_server' do
      expect(subject.name).to eq :percona_server
    end

    it 'should carry the version (one template per release)' do
      subject.version = "42.23"
      expect(subject.name).to eq :"percona_server@42.23"
    end
  end

  describe 'human_name' do
    it 'should name the product and the version' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "Percona Server 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker = double CloudModel::Workers::Components::PerconaServerComponentWorker

      expect(CloudModel::Workers::Components::PerconaServerComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker
      expect(subject.worker template, host).to eq worker
    end
  end

  describe 'requirements' do
    it 'should have no requirements' do
      expect(subject.requirements).to eq []
    end
  end
end
