# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Fuseki do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 3030 }

  describe 'kind' do
    it 'should return :http' do
      expect(subject.kind).to eq :http
    end
  end

  describe 'components_needed' do
    it 'should require solr components' do
      # java is required by solr component dependencies
      expect(subject.components_needed).to eq [:fuseki]
    end
  end

  describe 'read_server_info' do
    pending
  end

  describe 'service_status' do
    pending
  end

  describe 'heap_size' do
    pending
  end
end