# encoding: UTF-8

require 'spec_helper'

describe CloudModel::AddressResolution do
  it { is_expected.to have_timestamps }

  it { expect(subject).to have_field(:ip).of_type String }
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:active).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:ptr_active).of_type(Mongoid::Boolean).with_default_value_of true }

  describe '.for' do

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
      expect(subject.errors[:ip]).to eq ["is already taken"]
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