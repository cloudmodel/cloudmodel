# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Neo4j do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 7687 }

  describe 'kind' do
    it 'should return :neo4j' do
      expect(subject.kind).to eq :neo4j
    end
  end

  describe 'components_needed' do
    it 'should require neo4j component' do
      expect(subject.components_needed).to eq [:neo4j]
    end
  end

  describe 'service_status' do
    it 'should return an empty hash' do
      expect(subject.service_status).to eq({})
    end
  end
end
