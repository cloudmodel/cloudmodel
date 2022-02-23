module CloudModel

  # Handle IP addresses
  class Address
    require 'netaddr'

    include Mongoid::Document
    include Mongoid::Timestamps

    embedded_in :host, :polymorphic => true

    field :ip, type: String # @return [String] IP Address or subnet base address
    field :subnet, type: Integer # @return [Integer] Subnet as bitmask
    # Gateway for the address block
    field :gateway, type: String

    validates :ip, presence: true
    validates :subnet, presence: true

    validate :check_ip_format

    # Initialize CloudModel::Address from a string
    # @param str Sting in format of IP address and bitmask
    # @return [CloudModel::Address]
    def self.from_str(str)
      net = ::NetAddr.parse_net(str)
      ip = ::NetAddr.parse_ip(str.split(/[\/ ]/).first)

      self.new ip: ip.to_s, subnet: net.netmask.to_s.gsub(/^\//, '')
    end

    # Get Address as string
    # @return String in format of IP address and bitmask
    def to_s options={}
      if ip and subnet
        "#{ip}/#{subnet}"
      else
        ""
      end
    end

    # Get resolved hostname for Address
    # @return [String]
    def hostname
      if resolution = CloudModel::AddressResolution.where(ip: ip).first
        resolution.name
      else
        begin
          Resolv.getname(ip)
        rescue
          ip
        end
      end
    end

    # Get netmask in bitmask form
    def network
      cidr.network.to_s
    end

    # Get netmask in extended form for IPv4
    def netmask
      if ip_version == 4
        cidr.netmask.extended
      else
        cidr.netmask.to_s
      end
    end

    # Get broadcast address for address block
    def broadcast
      cidr.nth(cidr.len - 1).to_s if ip_version == 4
    end

    # Get version of IP protocol
    def ip_version
      cidr.version
    end

    # Check if Address is a range
    def range?
      ip == network
    end

    def private?
      if ip_version == 6
        ip =~ /^f[cd][0-9a-f]{2}:/ or ip =~ /^::1/ or ip =~ /^fe[c-f][0-9a-f]:/
      else
        ip_parts = ip.split('.').map &:to_i

        ip_parts[0] == 10 or
        (ip_parts[0] == 192 and ip_parts[1] == 168) or
        (ip_parts[0] == 169 and ip_parts[1] == 254) or
        ip == '127.0.0.1' or
        (ip_parts[0] == 172 and ip_parts[1] >= 16 and ip_parts[1] <= 31) or
        (ip_parts[0] == 100 and ip_parts[1] >= 64 and ip_parts[1] <= 127)
      end ? true : false
    end

    def public?
      not private?
    end

    # Get array of all IPv4 addresses in address block
    def list_ips options={}
      if ip_version==6
        # Only list ips that have a resolutions
        AddressResolution.for_subnet(self).map &:ip
      else
        if range?
          ips = []
          if options[:include_network]
            ips << cidr.nth(0).to_s
          end
          (cidr.len - 2).times do |i|
            ips << cidr.nth(i + 1).to_s
          end
          if options[:include_gateway]
            ips << cidr.nth(cidr.len - 1).to_s
          end
          ips
          #cidr.to_a#.enumerate[1..-2]
        else
          [ip]
        end
      end
    end

    # Get tinc subnet bitmask
    def tinc_subnet
      if CloudModel.config.tinc_network
        NetAddr.parse_net(CloudModel.config.tinc_network).netmask.to_s.gsub(/^\//, '').to_i
      else
        16
      end
    end

    # Get tinc network
    def tinc_network
      if CloudModel.config.tinc_network
        NetAddr.parse_net(CloudModel.config.tinc_network).network.to_s
      else
        '10.42.0.0'
      end
    end

    # get NetAddr object
    def cidr
      if subnet
        ::NetAddr.parse_net("#{ip}/#{subnet}")
      else
        ::NetAddr.parse_net(ip)
      end
    end

    private
    # Check format of ip
    def check_ip_format
      begin
        ::NetAddr.parse_net("#{ip}/#{subnet}")
      rescue Exception => e
        self.errors.add(:subnet, :format, default: e.message)
        return false
      end
    end
  end
end