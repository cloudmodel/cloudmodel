# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Components::SolrComponent do
  it { expect(subject).to be_a CloudModel::Components::BaseComponent }
  
  describe 'name' do
    it 'should return :solr' do
      expect(subject.name).to eq :solr
    end
  end
  
  describe 'requirements' do
    it 'should require :java' do
      expect(subject.requirements).to eq [:java]
    end
  end
end