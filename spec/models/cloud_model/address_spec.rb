# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Address do
  it { is_expected.to have_timestamps }
  
  it { expect(subject).to be_embedded_in(:host).of_type CloudModel::Host }
  
  it { expect(subject).to have_field(:ip).of_type String }
  it { expect(subject).to have_field(:subnet).of_type Integer }
  it { expect(subject).to have_field(:gateway).of_type String }
  
  it { expect(subject).to validate_presence_of(:ip) }
  it { expect(subject).to validate_presence_of(:subnet) }
  
  context '#from_str' do
    it "should accept IPV4 address without subnet" do
      address = CloudModel::Address.from_str('10.42.23.1')
      expect(address.ip).to eq '10.42.23.1'
      expect(address.subnet).to eq 32
    end
    
    it "should accept IPV4 address with subnet" do
      address = CloudModel::Address.from_str('10.42.23.1/16')
      expect(address.ip).to eq '10.42.23.1'
      expect(address.subnet).to eq 16
    end
    
    it "should accept IPV4 address with netmask" do
      address = CloudModel::Address.from_str('10.42.23.1 255.255.255.240')
      expect(address.ip).to eq '10.42.23.1'
      expect(address.subnet).to eq 28
    end
    
    it "should accept IPV6 address with subnet" do
      address = CloudModel::Address.from_str('fec0::1/64')
      expect(address.ip).to eq 'fec0::1'
      expect(address.subnet).to eq 64
    end
  end
  
  context 'to_s' do
    it "should get IPV4 string" do
      subject.ip = '10.42.23.1'
      subject.subnet = 30
      expect(subject.to_s).to eq '10.42.23.1/30'
    end
    
    it "should get IPV6 string" do
      subject.ip = 'fec0::'
      subject.subnet = 64
      expect(subject.to_s).to eq 'fec0::/64'
    end
  end
  
  context 'hostname' do
    it 'should return set hostname if given' do
      subject.hostname = 'some.host.name'
      expect(subject.hostname).to eq 'some.host.name'
    end
    
    it 'should resolve ip if not hostname is given' do
      subject.ip = '10.42.23.1'
      expect(Resolv).to receive(:getname).with('10.42.23.1').and_return 'some.host.name'
      expect(subject.hostname).to eq 'some.host.name'
    end
  end
  
  context 'network' do
    it "should get IPV4 netmask" do
      subject.ip = '10.42.23.130'
      subject.subnet = 30
      expect(subject.network).to eq '10.42.23.128'
    end
    
    it "should get IPV6 netmask" do
      subject.ip = 'fec0::'
      subject.subnet = 64
      expect(subject.network).to eq 'fec0::'
    end
  end  
  
  context 'netmask' do
    it "should get IPV4 netmask" do
      subject.ip = '10.42.23.1'
      subject.subnet = 30
      expect(subject.netmask).to eq '255.255.255.252'
    end
    
    it "should get IPV6 netmask" do
      subject.ip = 'fec0::'
      subject.subnet = 64
      expect(subject.netmask).to eq '/64'
    end
  end
  
  context 'broadcast' do
    it "should get IPV4 broadcast" do
      subject.ip = '10.42.23.1'
      subject.subnet = 30
      expect(subject.broadcast).to eq '10.42.23.3'
    end
    
    it "should not get IPV6 broadcast (as there is no such thing)" do
      subject.ip = 'fec0::'
      subject.subnet = 64
      expect(subject.broadcast).to be_nil
    end
  end
  
  context 'ip_version' do
    it "should get IPV4 version" do
      subject.ip = '10.42.23.1'
      subject.subnet = 30
      expect(subject.ip_version).to eq 4
    end
    
    it "should get IPV6 version" do
      subject.ip = 'fec0::'
      subject.subnet = 64
      expect(subject.ip_version).to eq 6
    end
  end
  
  context 'range?' do
    it "should find out that it is an range when given network ip" do
      subject.ip = '127.0.0.0'
      subject.subnet = 24
      expect(subject).to be_range
    end
  
    it "should find out that it is an network when given non network ip" do
      subject.ip = '127.0.0.1'
      subject.subnet = 24
      expect(subject).not_to be_range
    end
  end
  
  context 'list_ips' do
    it "should return range if address is range" do
      subject.ip = '10.42.23.0'
      subject.subnet = 30
      expect(subject.list_ips).to eq ["10.42.23.1", "10.42.23.2"]
    end
    
    it "should return ip in array if address is ip" do
      subject.ip = '10.42.23.2'
      subject.subnet = 30
      expect(subject.list_ips).to eq ["10.42.23.2"]
    end
  end
  
  context 'tinc_subnet' do
    it 'should return 16 (always for now)' do
      expect(subject.tinc_subnet).to eq 16
    end
  end
  
  context 'tinc_network' do
    it 'should get private network from last host and return base address for tinc_subnet' do
      network = CloudModel::Address.new ip: '10.42.23.16', subnet: 24
      allow(CloudModel::Host).to receive(:last).and_return(double :host, private_network: network)
      expect(subject.tinc_network).to eq "10.42.0.0"
    end
  end
  
  context "validates data" do
    it "should not accept invalid IP addresses" do
      subject.ip = "10.43.0.256"
      subject.subnet = 28
      expect(subject).not_to be_valid
    end
  end
  
end