# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Solr do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 8080 }
  it { expect(subject).to belong_to(:deploy_solr_image).of_type(CloudModel::SolrImage).as_inverse_of :services }

  describe 'kind' do
    it 'should return :http' do
      expect(subject.kind).to eq :http
    end
  end

  describe 'components_needed' do
    it 'should require solr components' do
      expect(subject).to receive(:deploy_solr_image).and_return(double solr_version: '42.23')
      # java is required by solr component dependencies
      expect(subject.components_needed).to eq [:'solr@42.23']
    end
  end

  describe 'read_solr_json' do
    pending
  end

  describe 'service_status' do
    pending
  end

  describe 'heap_size' do
    pending
  end
end