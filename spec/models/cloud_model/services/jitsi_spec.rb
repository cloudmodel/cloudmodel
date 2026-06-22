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
    it 'should return an empty hash' do
      expect(subject.service_status).to eq({})
    end
  end
end
