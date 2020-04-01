# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Solr do
  it { expect(subject).to be_a CloudModel::Services::Base }
  
  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 8080 }
  it { expect(subject).to belong_to(:deploy_solr_image).of_type(CloudModel::SolrImage).as_inverse_of :services }
  
  context 'kind' do
    it 'should return :http' do
      expect(subject.kind).to eq :http
    end
  end
  
  context 'components_needed' do
    it 'should require java and solr components' do
      expect(subject.components_needed).to eq [:java, :solr]
    end
  end

  context 'read_solr_json' do
    pending
  end

  context 'service_status' do 
    pending
  end
  
  context 'heap_size' do
    pending
  end
end