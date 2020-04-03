# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::SolrComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }
  
  context 'name' do
    it 'should return :solr' do
      expect(subject.name).to eq :solr
    end
  end
  
  context 'requirements' do
    it 'should require :java' do
      expect(subject.requirements).to eq [:java]
    end
  end
end