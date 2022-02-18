# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::SolrComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }

  describe 'base_name' do
    it 'should return "solr"' do
      expect(subject.base_name).to eq 'solr'
    end

    it 'should return "solr" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'solr'
    end
  end

  describe 'name' do
    it 'should return :solr' do
      expect(subject.name).to eq :solr
    end

    it 'should return :solr@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'solr@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "Solr"' do
      expect(subject.human_name).to eq "Solr"
    end

    it 'should return "Solr 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "Solr 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      worker_class = double CloudModel::Workers::Components::SolrComponentWorker

      expect(CloudModel::Workers::Components::SolrComponentWorker).to receive(:new).with(host, component: subject).and_return worker_class
      expect(subject.worker host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require :java8' do
      expect(subject.requirements).to eq [:java8]
    end
  end
end