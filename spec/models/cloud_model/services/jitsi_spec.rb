# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Jitsi do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 10000 }
  it { expect(subject).to have_field(:videobridge_port).of_type(Integer).with_default_value_of 9090 }
  it { expect(subject).to have_field(:stun_port).of_type(Integer).with_default_value_of 3478 }
  it { expect(subject).to have_field(:turn_port).of_type(Integer).with_default_value_of 5349 }

  describe 'kind' do
    it 'should return :jitsi' do
      expect(subject.kind).to eq :jitsi
    end
  end

  describe 'allow_public_service?' do
    it 'should allow public exposure' do
      expect(subject.allow_public_service?).to eq true
    end
  end

  describe 'components_needed' do
    it 'should require jitsi component' do
      expect(subject.components_needed).to eq [:jitsi]
    end
  end

  describe 'used_ports' do
    it 'should return media, videobridge, stun and turn ports' do
      expect(subject.used_ports).to eq [
        [10000, :udp],
        [9090, :tcp],
        [3478, :udp],
        [5349, :tcp]
      ]
    end

    it 'should reflect custom port values' do
      subject.port = 20000
      subject.videobridge_port = 8080
      subject.stun_port = 3479
      subject.turn_port = 5350

      expect(subject.used_ports).to eq [
        [20000, :udp],
        [8080, :tcp],
        [3479, :udp],
        [5350, :tcp]
      ]
    end
  end

  describe 'service_status' do
    let(:guest) { double CloudModel::Guest, private_address: '10.0.0.6' }
    before { allow(subject).to receive(:guest).and_return guest }

    let(:stats_body) do
      '{"bridge_selector":{"operational_bridge_count":1,"bridge_count":1,"lost_bridges":0},' \
      '"conferences":2,"participants":5,"largest_conference":3,' \
      '"total_conferences_created":38,"total_participants":78,' \
      '"participant_notifications":{"ice_failed":0},"bridge_failures":{"bridges_removed":0},' \
      '"threads":27,"version":"1.0.1066"}'
    end

    it 'reports bridge/conference metrics from Jicofo stats and videobridge liveness' do
      allow(subject).to receive(:monitoring_tcp_open?).and_return true
      allow(subject).to receive(:monitoring_http_get).and_return(double code: '200', body: stats_body)

      status = subject.service_status
      expect(status['operational_bridges']).to eq 1
      expect(status['videobridge_up']).to eq 1
      expect(status['conferences']).to eq 2
      expect(status['ice_failed']).to eq 0
      expect(status['version']).to eq '1.0.1066'
    end

    it 'returns a critical not_reachable error when Jicofo is down' do
      allow(subject).to receive(:monitoring_tcp_open?).and_return false
      allow(subject).to receive(:monitoring_http_get).and_raise Errno::ECONNREFUSED
      expect(subject.service_status[:key]).to eq :not_reachable
    end

    it 'warns when the Jicofo stats endpoint returns non-200' do
      allow(subject).to receive(:monitoring_tcp_open?).and_return true
      allow(subject).to receive(:monitoring_http_get).and_return(double code: '404', body: '')
      expect(subject.service_status[:key]).to eq :no_jicofo_stats
    end
  end
end
