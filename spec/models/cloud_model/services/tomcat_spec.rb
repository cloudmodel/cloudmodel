# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Tomcat do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject.allow_public_service?).to eq false }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 8080 }
  it { expect(subject).to belong_to(:deploy_war_image).of_type(CloudModel::WarImage).as_inverse_of :services }

  describe 'kind' do
    it 'should return :http' do
      expect(subject.kind).to eq :http
    end
  end

  describe 'components_needed' do
    it 'should require java and tomcat components' do
      expect(subject.components_needed).to eq [:tomcat]
    end
  end

  let(:guest) { double CloudModel::Guest, internal_address: '10.42.0.1', memory_size: 512 * 1024 * 1024 }
  before { allow(subject).to receive(:guest).and_return(guest) }

  describe 'service_status' do
    it 'should return parsed XML status data on success' do
      xml = <<~XML
        <status>
          <jvm><memory free="100" total="256" max="512"/></jvm>
          <connector name='"http-nio-8080"'>
            <requestInfo maxTime="100" processingTime="500" requestCount="42" errorCount="0" bytesReceived="1024" bytesSent="2048"/>
            <threadInfo maxThreads="200" currentThreadCount="10" busyThread="2"/>
          </connector>
        </status>
      XML
      response = double 'response', code: '200', body: xml, http_version: '1.1'
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })

      result = subject.service_status
      expect(result['memory_free']).to eq 100
      expect(result['memory_total']).to eq 256
      expect(result['http_version']).to eq '1.1'
    end

    it 'should return error hash when connection fails' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end
  end

  describe 'heap_size' do
    it 'should return memory minus 128m' do
      expect(subject.heap_size).to eq '384m'
    end
  end
end