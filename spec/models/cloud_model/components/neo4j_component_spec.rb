# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::Neo4jComponent do
  it { expect(subject).to be_a CloudModel::Components::Neo4jComponent }

  describe 'base_name' do
    it 'should return "neo4j"' do
      expect(subject.base_name).to eq 'neo4j'
    end

    it 'should return "neo4j" if version is set' do
      subject.version = "42.23"
      expect(subject.base_name).to eq 'neo4j'
    end
  end

  describe 'name' do
    it 'should return :neo4j' do
      expect(subject.name).to eq :neo4j
    end

    it 'should return :neo4j@42.23 if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.name).to eq :'neo4j@42.23'
    end
  end

  describe 'human_name' do
    it 'should return "Neo4j"' do
      expect(subject.human_name).to eq "Neo4j"
    end

    it 'should return "Neo4j 42.23" if version is set to 42.23' do
      subject.version = "42.23"
      expect(subject.human_name).to eq "Neo4j 42.23"
    end
  end

  describe 'worker' do
    it 'should return worker instance' do
      host = double CloudModel::Host
      template = double
      worker_class = double CloudModel::Workers::Components::Neo4jComponentWorker

      expect(CloudModel::Workers::Components::Neo4jComponentWorker).to receive(:new).with(template, host, {component: subject}).and_return worker_class
      expect(subject.worker template, host).to eq worker_class
    end
  end

  describe 'requirements' do
    it 'should require java' do
      expect(subject.requirements).to eq [:java]
    end
  end
end
