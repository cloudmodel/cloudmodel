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

  let(:guest) { double CloudModel::Guest, private_address: '10.42.0.1', memory_size: 512 * 1024 * 1024 }
  before { allow(subject).to receive(:guest).and_return(guest) }

  describe 'read_server_info' do
    it 'should return error hash when HTTP fails' do
      uri = URI('http://10.42.0.1:3030/$/metrics')
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      result = subject.read_server_info(uri)
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end

    it 'should return warning on 404' do
      uri = URI('http://10.42.0.1:3030/$/metrics')
      response = double 'response', code: '404', body: ''
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })

      result = subject.read_server_info(uri)
      expect(result[:key]).to eq :no_fuseki_status
      expect(result[:severity]).to eq :warning
    end

    it 'should return warning on 401' do
      uri = URI('http://10.42.0.1:3030/$/metrics')
      response = double 'response', code: '401', body: ''
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })

      result = subject.read_server_info(uri)
      expect(result[:key]).to eq :fuseki_status_forbidden
      expect(result[:severity]).to eq :warning
    end
  end

  describe 'service_status' do
    it 'should call read_server_info with metrics URI' do
      data = {'jvm' => {'heap' => 42}}
      allow(subject).to receive(:read_server_info).and_return(data)

      expect(subject.service_status).to eq data
    end
  end

  describe 'heap_size' do
    it 'should return memory minus 128m' do
      expect(subject.heap_size).to eq '384m'
    end
  end
end