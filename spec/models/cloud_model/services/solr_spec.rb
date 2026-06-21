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

  let(:guest) { double CloudModel::Guest, private_address: '10.42.0.1', memory_size: 512 * 1024 * 1024 }
  before { allow(subject).to receive(:guest).and_return(guest) }

  describe 'read_solr_json' do
    it 'should return parsed JSON on success' do
      uri = URI('http://10.42.0.1:8080/solr/admin/info/system?wt=json')
      response = double 'response', code: '200', body: '{"jvm":{"memory":{"raw":{"free":100}}}}'
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })

      result = subject.read_solr_json(uri)
      expect(result['jvm']['memory']['raw']['free']).to eq 100
    end

    it 'should return error hash when connection fails' do
      uri = URI('http://10.42.0.1:8080/solr/admin/info/system?wt=json')
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      result = subject.read_solr_json(uri)
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end

    it 'should return warning on 404' do
      uri = URI('http://10.42.0.1:8080/solr/admin')
      response = double 'response', code: '404', body: ''
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })

      result = subject.read_solr_json(uri)
      expect(result[:key]).to eq :no_solr_status
    end
  end

  describe 'service_status' do
    it 'should build data from system status and cores status' do
      status = {'jvm' => {'jmx' => {'startTime' => '2024-01-01T00:00:00Z'}, 'memory' => {'raw' => {'free' => 100, 'total' => 256, 'used%' => 50.0}}}}
      cores = {'status' => {'core1' => {'startTime' => '2024-01-01T00:00:01Z'}}}
      allow(subject).to receive(:read_solr_json).and_return(status, cores)

      result = subject.service_status
      expect(result['memory_free']).to eq 100
      expect(result['cores_running']).to eq 1
    end

    it 'should return parse error when status data is invalid' do
      allow(subject).to receive(:read_solr_json).and_return({key: :not_reachable, error: 'fail', severity: :critical})

      result = subject.service_status
      expect(result[:key]).to eq :parse_result
      expect(result[:severity]).to eq :warning
    end
  end

  describe 'heap_size' do
    it 'should return memory minus 128m' do
      expect(subject.heap_size).to eq '384m'
    end
  end
end