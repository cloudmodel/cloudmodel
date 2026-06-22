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

  describe 'allow_public_service?' do
    it 'should not allow public exposure' do
      expect(subject.allow_public_service?).to eq false
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

    def stub_response(body, code: '200')
      uri = URI('http://10.42.0.1:3030/$/metrics')
      response = double 'response', code: code, body: body
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })
      uri
    end

    it 'should skip comment lines and parse jvm metrics into nested hash' do
      body = <<~METRICS
        # HELP jvm_memory_used Used memory
        # TYPE jvm_memory_used gauge
        jvm_memory_used{area="heap",id="G1 Eden Space"} 12340000
      METRICS
      uri = stub_response(body)

      result = subject.read_server_info(uri)
      # Source quirk: plain integers (no decimal point) fail the float regex and
      # the `value.to_i.to_f == value` check compares Float to String, so they
      # remain strings.
      expect(result['jvm']['memory_used']['heap']['G1 Eden Space']).to eq '12340000'
    end

    it 'should parse jvm_gc_ metrics under jvm.gc path' do
      body = <<~METRICS
        jvm_gc_pause_seconds_count{action="end of minor GC",cause="G1 Evacuation Pause"} 7
      METRICS
      uri = stub_response(body)

      result = subject.read_server_info(uri)
      # jvm_gc_ -> path ['jvm','gc'] then ['gc', 'pause_seconds_count']
      expect(result['jvm']['gc']).to be_a Hash
    end

    it 'should parse fuseki_ metrics and strip leading slash from dataset' do
      body = <<~METRICS
        fuseki_requests_good{dataset="/ds"} 5
      METRICS
      uri = stub_response(body)

      result = subject.read_server_info(uri)
      # dataset "/ds" -> "ds" pushed under path; plain int stays a string (see quirk above)
      expect(result['fuseki']['requests_good']['ds']).to eq '5'
    end

    it 'should coerce float-formatted values to float' do
      body = <<~METRICS
        jvm_memory_committed{area="nonheap"} 1.5E7
      METRICS
      uri = stub_response(body)

      result = subject.read_server_info(uri)
      # 1.5E7 = 15000000.0, .to_i.to_f == value so stored as int
      expect(result['jvm']['memory_committed']['nonheap']).to eq 15000000
    end

    it 'should keep non-integer floats as floats' do
      body = <<~METRICS
        jvm_buffer_ratio{id="direct"} 1.5
      METRICS
      uri = stub_response(body)

      result = subject.read_server_info(uri)
      expect(result['jvm']['buffer_ratio']['direct']).to eq 1.5
    end

    it 'should capture description attribute alongside value' do
      body = <<~METRICS
        fuseki_requests_good{dataset="/ds",description="all good requests"} 5
      METRICS
      uri = stub_response(body)

      result = subject.read_server_info(uri)
      expect(result['fuseki']['requests_good']['ds_description']).to eq 'all good requests'
    end

    it 'should return parse_result warning when body cannot be parsed' do
      # a line with no { } braces makes the regex match return nil -> NoMethodError on captures
      uri = stub_response("totally invalid not a metric line\n")

      result = subject.read_server_info(uri)
      expect(result[:key]).to eq :parse_result
      expect(result[:severity]).to eq :warning
      expect(result[:error]).to include 'can\'t parse prometheus format'
    end
  end

  describe 'service_status' do
    it 'should call read_server_info with metrics URI' do
      data = {'jvm' => {'heap' => 42}}
      allow(subject).to receive(:read_server_info).and_return(data)

      expect(subject.service_status).to eq data
    end

    it 'should build metrics URI from guest private_address and port' do
      data = {}
      expect(subject).to receive(:read_server_info) do |uri|
        expect(uri.to_s).to eq 'http://10.42.0.1:3030/$/metrics'
        data
      end

      expect(subject.service_status).to eq data
    end
  end

  describe 'heap_size' do
    it 'should return memory minus 128m' do
      expect(subject.heap_size).to eq '384m'
    end
  end
end