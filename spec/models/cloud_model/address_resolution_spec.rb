# encoding: UTF-8

require 'spec_helper'

describe CloudModel::AddressResolution do
  it { is_expected.to have_timestamps }

  it { expect(subject).to have_field(:ip).of_type String }
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:alt_names).of_type Array }
  it { expect(subject).to have_field(:active).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:ptr_active).of_type(Mongoid::Boolean).with_default_value_of true }

  describe '.for_subnet' do
    it 'should return resolutions for all IPv4 addresses in subnet' do
      subnet = double CloudModel::Address, ip_version: 4
      allow(CloudModel::Address).to receive(:from_str).with('10.42.0.0/28').and_return subnet
      allow(subnet).to receive(:list_ips).with(include_network: true, include_gateway: true).and_return(['10.42.0.0', '10.42.0.1'])

      resolution = double CloudModel::AddressResolution
      expect(CloudModel::AddressResolution).to receive(:find_or_initialize_by).with(ip: '10.42.0.0').and_return(resolution)
      expect(CloudModel::AddressResolution).to receive(:find_or_initialize_by).with(ip: '10.42.0.1').and_return(resolution)

      result = CloudModel::AddressResolution.for_subnet('10.42.0.0/28')
      expect(result.size).to eq 2
    end

    it 'should query by prefix for IPv6 subnets' do
      subnet = double CloudModel::Address, ip_version: 6, ip: double(to_s: 'dead:beef::')
      allow(CloudModel::Address).to receive(:from_str).with(subnet).and_return subnet

      criteria = double 'criteria'
      expect(CloudModel::AddressResolution).to receive(:where).with(ip: /\Adead:beef::/).and_return(criteria)

      CloudModel::AddressResolution.for_subnet(subnet)
    end
  end

  describe '#address' do
    it 'should get an CloudModel::Address from given ip' do
      subject.ip = '127.0.0.1'
      address = double CloudModel::Address
      expect(CloudModel::Address).to receive(:from_str).with('127.0.0.1').and_return address
      expect(subject.address).to eq address
    end
  end

  describe '#cidr' do
    it 'should get cidr from CloudModel::Address' do
      address = double CloudModel::Address
      cidr = double
      expect(subject).to receive(:address).and_return address
      expect(address).to receive(:cidr).and_return cidr
      expect(subject.cidr).to eq cidr
    end
  end

  describe '#alt_addresses' do
    it 'should return other resolutions with same name but different ip' do
      subject.ip = '10.0.0.1'
      subject.name = 'host.example.com'

      criteria = double 'criteria'
      expect(CloudModel::AddressResolution).to receive(:where).with(name: 'host.example.com', :ip.ne => '10.0.0.1').and_return(criteria)

      expect(subject.alt_addresses).to eq criteria
    end
  end

  describe '#alt_ips' do
    it 'should return ips of alt_addresses' do
      alt1 = double CloudModel::AddressResolution, ip: '10.0.0.2'
      alt2 = double CloudModel::AddressResolution, ip: '10.0.0.3'
      allow(subject).to receive(:alt_addresses).and_return([alt1, alt2])

      expect(subject.alt_ips).to eq ['10.0.0.2', '10.0.0.3']
    end
  end

  describe 'ip validator' do
    before do
      subject.name = 'host.example.com'
    end

    it 'should accept valid ipv4 address' do
      subject.ip = '10.42.23.13'
      expect(subject).to be_valid
    end

    it 'should accept valid ipv6 address' do
      subject.ip = 'dead:beef::42'
      expect(subject).to be_valid
    end

    it 'should not accept invalid ips' do
      subject.ip = 'foo:bar'
      expect(subject).not_to be_valid
      expect(subject.errors[:ip]).to eq ["is invalid"]
    end

    it 'should not accept invalid ipv4' do
      subject.ip = '280.1.1.1'
      expect(subject).not_to be_valid
      expect(subject.errors[:ip]).to eq ["is invalid"]
    end

    it 'should not accept invalid ipv6' do
      subject.ip = 'dead::beaf::42'
      expect(subject).not_to be_valid
      expect(subject.errors[:ip]).to eq ["is invalid"]
    end

    it 'should not accept valid ipv4 subnet' do
      subject.ip = '10.42.23.13/28'
      expect(subject).not_to be_valid
      expect(subject.errors[:ip]).to eq ["is invalid"]
    end

    it 'should not accept valid ipv6 subnet' do
      subject.ip = 'dead:beef::42/64'
      expect(subject).not_to be_valid
      expect(subject.errors[:ip]).to eq ["is invalid"]
    end

    it 'should not accept blank ip' do
      subject.ip = nil
      expect(subject).not_to be_valid
      expect(subject.errors[:ip]).to eq ["is invalid"]
    end

    it 'should not accept an ip twice' do
      CloudModel::AddressResolution.create! ip: '10.42.23.13', name: 'test.example.com'
      subject.ip = '10.42.23.13'
      expect(subject).not_to be_valid
      expect(subject.errors[:ip]).to eq ["has already been taken"]
    end
  end

  describe 'name validator' do
    before do
      subject.ip = '127.0.0.1'
    end

    it 'should accept valid domain name' do
      subject.name = "example.com"
      expect(subject).to be_valid
    end

    it 'should accept valid subdomain name' do
      subject.name = "test.example.com"
      expect(subject).to be_valid
    end
  end
end