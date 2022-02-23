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

  describe '#from_str' do
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

  describe 'to_s' do
    it "should return IPV4 string" do
      subject.ip = '10.42.23.1'
      subject.subnet = 30
      expect(subject.to_s).to eq '10.42.23.1/30'
    end

    it "should return IPV6 string" do
      subject.ip = 'fec0::'
      subject.subnet = 64
      expect(subject.to_s).to eq 'fec0::/64'
    end

    it "should return empty String if no ip is set" do
      expect(subject.to_s).to eq ''
    end
  end

  describe 'hostname' do
    it 'should return hostname via resolution if given' do
      subject.ip = '10.42.23.1'
      resolution = double CloudModel::AddressResolution, name: 'some.host.name'
      expect(CloudModel::AddressResolution).to receive(:where).with(ip: '10.42.23.1').and_return [resolution]
      expect(Resolv).not_to receive(:getname)
      expect(subject.hostname).to eq 'some.host.name'
    end

    it 'should resolve ip if not hostname is given and no resolution found' do
      subject.ip = '10.42.23.1'
      expect(CloudModel::AddressResolution).to receive(:where).with(ip: '10.42.23.1').and_return []
      expect(Resolv).to receive(:getname).with('10.42.23.1').and_return 'some.host.name'
      expect(subject.hostname).to eq 'some.host.name'
    end

    it 'should fallback to ip if neither is met' do
      subject.ip = '10.42.23.1'
      expect(CloudModel::AddressResolution).to receive(:where).with(ip: '10.42.23.1').and_return []
      expect(Resolv).to receive(:getname).with('10.42.23.1').and_raise 'not found'
      expect(subject.hostname).to eq '10.42.23.1'
    end
  end

  describe 'network' do
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

  describe 'netmask' do
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

  describe 'broadcast' do
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

  describe 'ip_version' do
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

  describe 'range?' do
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

  describe '#private?' do
    10.times do
      it 'should consider private addresses 10.0.0.0/8 as private' do
        # 10.0.0.0 - 10.255.255.255
        subject.ip = "10.#{rand(0..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(true), "#{subject.ip} should be private"
      end

      it 'should consider private addresses 172.16.0.0/12 as private' do
        # 172.16.0.0 - 172.31.255.255
        subject.ip = "172.#{rand(16..31)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(true), "#{subject.ip} should be private"
      end

      it 'should consider private addresses 192.168.0.0/16 as private' do
        # 192.168.0.0 - 192.168.255.255
        subject.ip = "192.168.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(true), "#{subject.ip} should be private"
      end

      it 'should consider shared addresses 100.64.0.0/10 as private' do
        # 100.64.0.0 - 100.127.255.255
        subject.ip = "100.#{rand(64..127)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(true), "#{subject.ip} should be private"
      end

      it 'should consider link local addresses 169.254.0.0/16 as private' do
        # 169.254.0.0 - 169.254.255.255
        subject.ip = "169.254.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(true), "#{subject.ip} should be private"
      end

      it 'should consider localhost 127.0.0.1 as private' do
        subject.ip = '127.0.0.1'
        expect(subject.private?).to eq(true), "#{subject.ip} should be private"
      end

      it 'should consider unique local addresses fc00::/7 as private' do
        # fc00:x - fdff:x
        subject.ip = "#{rand(0xfc00..0xfdff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}::"
        expect(subject.private?).to eq(true), "#{subject.ip} should be private"
      end

      it 'should consider site local addresses fec0::/10  as private' do
        # fec0:x - feff:x
        subject.ip = "#{rand(0xfec0..0xfeff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}::"
        expect(subject.private?).to eq(true), "#{subject.ip} should be private"
      end

      it 'should consider other ipv4 as public' do
        subject.ip = "#{rand(1..9)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "#{rand(11..99)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "100.#{rand(0..63)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "100.#{rand(128..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "#{rand(101..168)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "169.#{rand(0..253)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "169.255.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "#{rand(170..171)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "172.#{rand(0..15)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "172.#{rand(32..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "#{rand(173..191)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "192.#{rand(0..167)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "192.#{rand(169..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "#{rand(193..255)}.#{rand(0..255)}.#{rand(0..255)}.#{rand(0..255)}"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
      end

      it 'should consider other ipv6 as public' do
        subject.ip = "#{rand(0x1..0xfbff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}::"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "#{rand(0xfe00..0xfebf).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}::"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
        subject.ip = "#{rand(0xff00..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}:#{rand(0..0xffff).to_s 16}::"
        expect(subject.private?).to eq(false), "#{subject.ip} should not be private"
      end
    end
  end

  describe "#public?" do
    it 'should not be private' do
      expect(subject).to receive(:private?).and_return false
      expect(subject.public?).to be true
    end

    it 'should be not private' do
      expect(subject).to receive(:private?).and_return true
      expect(subject.public?).to be false
    end
  end

  describe '#list_ips' do
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

    it "should return only ips with AddressResolution IPv6 addresses" do
      subject.ip = 'fe::'
      subject.subnet = 64

      expect(CloudModel::AddressResolution).to receive(:for_subnet).with(subject).and_return [
        double(ip: 'fe::2'),
        double(ip: 'fe::23'),
        double(ip: 'fe::42')
      ]

      expect(subject.list_ips).to eq ["fe::2", "fe::23", "fe::42"]
    end

    it "should return empty array for IPv6 addresses if no AddressResolution" do
      subject.ip = 'fe::'
      subject.subnet = 64
      expect(subject.list_ips).to eq []
    end
  end

  describe 'tinc_subnet' do
    it 'should return configured tinc_network netmask if given' do
      allow(CloudModel.config).to receive(:tinc_network).and_return '10.42.23.0/24'

      expect(subject.tinc_subnet).to eq 24
    end

    it 'should return 16 if no tinc_network was configured' do
      allow(CloudModel.config).to receive(:tinc_network).and_return nil

      expect(subject.tinc_subnet).to eq 16
    end
  end

  describe 'tinc_network' do
    it 'should return configured tinc_network netmask if given' do
      allow(CloudModel.config).to receive(:tinc_network).and_return '10.23.42.0/24'

      expect(subject.tinc_network).to eq '10.23.42.0'
    end


    it 'should return 10.42.0.0 if no tinc_network was configured' do
      allow(CloudModel.config).to receive(:tinc_network).and_return nil

      expect(subject.tinc_network).to eq "10.42.0.0"
    end
  end

  describe 'validates data' do
    it 'should not accept invalid IP addresses' do
      subject.ip = "10.43.0.256"
      subject.subnet = 28
      expect(subject).not_to be_valid
    end
  end

  describe 'cidr' do
    it 'should get NetAddr net for ip and subnet' do
      net = double
      subject.ip = "10.42.23.12"
      subject.subnet = 28

      expect(NetAddr).to receive(:parse_net).with("10.42.23.12/28").and_return net

      expect(subject.send :cidr).to eq net
    end

    it 'should get NetAddr net for ip and no subnet' do
      net = double
      subject.ip = "10.42.23.12"

      expect(NetAddr).to receive(:parse_net).with("10.42.23.12").and_return net

      expect(subject.send :cidr).to eq net
    end
  end
end