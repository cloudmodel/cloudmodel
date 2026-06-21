require 'spec_helper'

describe CloudModel::Workers::FirewallWorker do
  let(:primary_address) { double 'primary_address', ip: '10.0.0.1' }
  let(:address1) do
    double 'address',
      ip: '192.168.1.0',
      ip_version: 4,
      list_ips: ['192.168.1.1'],
      to_s: '192.168.1.0/24'
  end
  let(:private_network) do
    double 'private_network',
      to_s: '10.42.0.0/16',
      tinc_network: '10.42.0.0',
      tinc_subnet: '16'
  end
  let(:guest_service) do
    double 'service',
      kind: :http,
      public_service: true,
      used_ports: [[80, :tcp]]
  end
  let(:guest) do
    double 'guest',
      private_address: '10.42.0.2',
      external_address: '192.168.1.1'
  end
  let(:sftp_file) { double 'sftp_file' }
  let(:sftp) { double 'sftp', file: sftp_file }
  let(:host) do
    double 'host',
      primary_address: primary_address,
      addresses: [address1],
      private_network: private_network,
      firewall_rules: [],
      guests: double('guests'),
      sftp: sftp
  end

  before do
    guest_services = double 'guest_services'
    allow(guest).to receive(:services).and_return(guest_services)
    allow(guest_services).to receive(:where).with(public_service: true).and_return([guest_service])
    allow(host.guests).to receive(:where).with(external_address: '192.168.1.1').and_return(double(first: guest))
    allow(host.guests).to receive(:where).with(:external_address.exists => true).and_return([guest])
  end

  subject { CloudModel::Workers::FirewallWorker.new host }

  describe '#ssh_deep_inspect?' do
    it 'should return false' do
      expect(subject.ssh_deep_inspect?).to eq false
    end
  end

  describe '#parse_ports' do
    it 'should wrap integer in array' do
      expect(subject.parse_ports(22)).to eq [22]
    end

    it 'should split string by spaces' do
      expect(subject.parse_ports('80 443')).to eq ['80', '443']
    end

    it 'should return array as-is' do
      expect(subject.parse_ports([80, 443])).to eq [80, 443]
    end
  end

  describe '#ip4tables_bin' do
    it 'should return /sbin/iptables' do
      expect(subject.ip4tables_bin).to eq '/sbin/iptables'
    end
  end

  describe '#ip6tables_bin' do
    it 'should return /sbin/ip6tables' do
      expect(subject.ip6tables_bin).to eq '/sbin/ip6tables'
    end
  end

  describe '#iptables_bin' do
    it 'should return ip4tables_bin for IPv4' do
      expect(subject.iptables_bin('192.168.1.1')).to eq '/sbin/iptables'
    end

    it 'should return ip6tables_bin for IPv6' do
      expect(subject.iptables_bin('fe80::1')).to eq '/sbin/ip6tables'
    end
  end

  describe '#iptables_bins' do
    it 'should return both iptables binaries' do
      expect(subject.iptables_bins).to eq ['/sbin/iptables', '/sbin/ip6tables']
    end
  end

  describe '#shebang' do
    it 'should return shell shebang line' do
      expect(subject.shebang).to eq "#!/bin/sh\n"
    end
  end

  describe '#nat' do
    it 'should generate PREROUTING, OUTPUT lo, and OUTPUT lxdbr0 rules' do
      commands = subject.nat('192.168.1.1', 'eth0', 80, 'tcp', '10.42.0.2')
      expect(commands).to include "/sbin/iptables -t nat -A PREROUTING -p tcp -d 192.168.1.1 --dport 80 -j DNAT --to-destination 10.42.0.2:80"
      expect(commands).to include "/sbin/iptables -t nat -A OUTPUT -p tcp -o lo -d 192.168.1.1 --dport 80 -j DNAT --to 10.42.0.2:80"
      expect(commands).to include "/sbin/iptables -t nat -A OUTPUT -p tcp -o lxdbr0 -d 192.168.1.1 --dport 80 -j DNAT --to 10.42.0.2:80"
    end
  end

  describe '#stop_script' do
    it 'should flush iptables rules for both ip versions' do
      script = subject.stop_script
      expect(script).to include "/sbin/iptables -F"
      expect(script).to include "/sbin/iptables -t nat -F"
      expect(script).to include "/sbin/ip6tables -F"
      expect(script).to include "/sbin/ip6tables -t nat -F"
    end

    it 'should remove SSH_ATTACKED chain' do
      script = subject.stop_script
      expect(script).to include "SSH_ATTACKED"
    end
  end

  describe '#list_script' do
    it 'should list rules for both ip versions' do
      script = subject.list_script
      expect(script).to include "/sbin/iptables -L"
      expect(script).to include "/sbin/iptables -t nat -L"
      expect(script).to include "/sbin/ip6tables -L"
      expect(script).to include "/sbin/ip6tables -t nat -L"
    end
  end

  describe '#start_script' do
    it 'should set up lxdbr0 forwarding' do
      script = subject.start_script
      expect(script).to include "/sbin/iptables -A FORWARD -i lxdbr0 -j ACCEPT"
      expect(script).to include "/sbin/iptables -A FORWARD -o lxdbr0 -j ACCEPT"
    end

    it 'should reject unknown tcp and udp at the end' do
      script = subject.start_script
      expect(script).to include "/sbin/iptables -A INPUT -i eth0 -m conntrack --ctstate NEW -p tcp -j REJECT"
      expect(script).to include "/sbin/iptables -A INPUT -i eth0 -m conntrack --ctstate NEW -p udp -j REJECT"
    end

    it 'should block ICMP timestamp requests' do
      script = subject.start_script
      expect(script).to include "/sbin/iptables -A INPUT -i eth0 -p icmp --icmp-type timestamp-request -j DROP"
      expect(script).to include "/sbin/iptables -A OUTPUT -o eth0 -p icmp --icmp-type timestamp-reply -j DROP"
    end
  end

  describe '#write_scripts' do
    it 'should create /etc/cloud_model/ directory and write three scripts' do
      allow(subject).to receive(:mkdir_p)
      file_handle = double 'file_handle'
      allow(file_handle).to receive(:puts)
      allow(sftp_file).to receive(:open).and_yield(file_handle)

      expect(subject).to receive(:mkdir_p).with('/etc/cloud_model/')
      expect(sftp_file).to receive(:open).with('/etc/cloud_model/firewall_start', 'w', 0700)
      expect(sftp_file).to receive(:open).with('/etc/cloud_model/firewall_stop', 'w', 0700)
      expect(sftp_file).to receive(:open).with('/etc/cloud_model/firewall_list', 'w', 0700)

      expect(subject.write_scripts).to eq true
    end
  end
end
