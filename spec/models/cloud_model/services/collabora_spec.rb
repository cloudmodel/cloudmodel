# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Collabora do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 9980 }
  it { expect(subject).to have_field(:wopi_host).of_type(String).with_default_value_of nil }

  describe 'kind' do
    it 'should return :collabora' do
      expect(subject.kind).to eq :collabora
    end
  end

  describe 'components_needed' do
    it 'should require collabora component' do
      expect(subject.components_needed).to eq [:collabora]
    end
  end

  describe 'service_status' do
    let(:guest) { double CloudModel::Guest, private_address: '10.0.0.5' }
    before { allow(subject).to receive(:guest).and_return guest }

    it 'returns discovery + capabilities status on success' do
      discovery = double code: '200', body: '<wopi-discovery><net-zone/></wopi-discovery>'
      caps = double body: '{"convert-to":{"available":true},"hasMobileSupport":true}'
      allow(subject).to receive(:monitoring_http_get).with(%r{/hosting/discovery}).and_return discovery
      allow(subject).to receive(:monitoring_http_get).with(%r{/hosting/capabilities}).and_return caps

      expect(subject.service_status).to eq(
        'code' => 200, 'discovery_ok' => true, 'convert_to' => 1, 'mobile_support' => 1
      )
    end

    it 'returns a critical not_reachable error when the server is down' do
      allow(subject).to receive(:monitoring_http_get).and_raise Errno::ECONNREFUSED
      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end

    it 'warns when the WOPI discovery endpoint is missing' do
      allow(subject).to receive(:monitoring_http_get).with(%r{/hosting/discovery}).and_return(double code: '404', body: '')
      result = subject.service_status
      expect(result[:key]).to eq :no_discovery
      expect(result[:severity]).to eq :warning
    end
  end
end
