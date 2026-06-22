# encoding: UTF-8

require 'spec_helper'

describe CloudModel::FirewallRule do
  it { is_expected.to have_timestamps }

  it { expect(subject).to be_embedded_in(:host).of_type CloudModel::Host }

  it { expect(subject).to have_field(:source_ip).of_type String }
  it { expect(subject).to have_field(:source_port).of_type Integer }
  it { expect(subject).to have_field(:target_ip).of_type String }
  it { expect(subject).to have_field(:target_port).of_type Integer }
  it { expect(subject).to have_field(:service_kind).of_type(String).with_default_value_of('generic') }
  it { expect(subject).to have_field(:protocol).of_type(String).with_default_value_of('tcp') }

  it { expect(subject).to validate_presence_of(:source_ip) }
  it { expect(subject).to validate_presence_of(:source_port) }
  it { expect(subject).to validate_presence_of(:target_ip) }
  it { expect(subject).to validate_presence_of(:target_port) }
  it { expect(subject).to validate_inclusion_of(:protocol).to_allow('tcp', 'udp') }

  describe '#name' do
    it 'should return a human-readable summary of the rule' do
      subject.source_ip = '0.0.0.0/0'
      subject.source_port = 443
      subject.target_ip = '10.42.1.10'
      subject.target_port = 8443
      expect(subject.name).to eq '0.0.0.0/0:443->10.42.1.10:8443'
    end
  end

  describe '#to_s' do
    it 'should return the human model name with the rule name' do
      subject.source_ip = '0.0.0.0/0'
      subject.source_port = 443
      subject.target_ip = '10.42.1.10'
      subject.target_port = 443
      expect(subject.to_s).to eq "Firewall Rule '0.0.0.0/0:443->10.42.1.10:443'"
    end
  end
end
