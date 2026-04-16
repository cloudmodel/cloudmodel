module CloudModel

  # Represents an IP address or subnet in CIDR notation, embedded in a {Host}.
  #
  # Addresses are stored as separate `ip` and `subnet` fields rather than a
  # single CIDR string so that individual components can be queried efficiently
  # in MongoDB. Use {.from_str} to construct an instance from a string like
  # `"192.168.1.0/24"`.
  class Address
    require 'netaddr'

    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [rw] host
    #   @return [CloudModel::Host] the host this address is embedded in (polymorphic)
    embedded_in :host, :polymorphic => true

    # @!attribute [rw] ip
    #   @return [String] the IP address or subnet base address (e.g. "192.168.1.10")
    field :ip, type: String

    # @!attribute [rw] subnet
    #   @return [Integer] the subnet prefix length as an integer bitmask (e.g. 24 for /24)
    field :subnet, type: Integer

    # @!attribute [rw] gateway
    #   @return [String, nil] the default gateway for this address block
    field :gateway, type: String

    validates :ip, presence: true
    validates :subnet, presence: true

    validate :check_ip_format

    # Constructs an Address from a CIDR notation string.
    #
    # @param str [String] address in CIDR notation, e.g. `"203.0.113.10/24"`
    # @return [CloudModel::Address] a new (unsaved) Address instance
    def self.from_str(str)
      net = ::NetAddr.parse_net(str)
      ip = ::NetAddr.parse_ip(str.split(/[\/ ]/).first)

      self.new ip: ip.to_s, subnet: net.netmask.to_s.gsub(/^\//, '')
    end

    # Returns the address as a CIDR string.
    #
    # @return [String] e.g. `"192.168.1.0/24"`, or an empty string if ip or subnet is blank
    def to_s options={}
      if ip and subnet
        "#{ip}/#{subnet}"
      else
        ""
      end
    end

    # Resolves the hostname for the IP address.
    #
    # Looks up an {AddressResolution} record first; falls back to a reverse DNS
    # lookup; returns the raw IP string if resolution fails.
    #
    # @return [String] the resolved hostname or the IP address itself
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

    # Returns the network address (zeroed host bits) as a string.
    # @return [String] e.g. `"192.168.1.0"`
    def network
      cidr.network.to_s
    end

    # Returns the netmask. For IPv4, returns dot-notation (e.g. `"255.255.255.0"`);
    # for IPv6, returns the prefix string.
    # @return [String]
    def netmask
      if ip_version == 4
        cidr.netmask.extended
      else
        cidr.netmask.to_s
      end
    end

    # Returns the broadcast address for an IPv4 subnet.
    # @return [String, nil] broadcast address, or nil for IPv6
    def broadcast
      cidr.nth(cidr.len - 1).to_s if ip_version == 4
    end

    # Returns the IP protocol version.
    # @return [Integer] `4` or `6`
    def ip_version
      cidr.version
    end

    # Returns true when the `ip` field equals the network address (i.e. this
    # address represents a subnet rather than a single host).
    # @return [Boolean]
    def range?
      ip == network
    end

    # Returns true when the IP belongs to a private/RFC-1918 or link-local range.
    # @return [Boolean]
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

    # @return [Boolean] true when the IP is publicly routable
    def public?
      not private?
    end

    # Returns all usable IP addresses in the subnet.
    #
    # For IPv4 ranges, yields host addresses between network and broadcast.
    # Pass options to include the network or broadcast address explicitly.
    # For IPv6, returns IPs that have an {AddressResolution} record.
    #
    # @param options [Hash]
    # @option options [Boolean] :include_network include the network address (IPv4 only)
    # @option options [Boolean] :include_gateway include the broadcast/gateway address (IPv4 only)
    # @return [Array<String>] list of IP address strings
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

    # Returns the prefix length of the configured tinc overlay network.
    # @return [Integer] e.g. `16` for a `/16` network
    def tinc_subnet
      if CloudModel.config.tinc_network
        NetAddr.parse_net(CloudModel.config.tinc_network).netmask.to_s.gsub(/^\//, '').to_i
      else
        16
      end
    end

    # Returns the network address of the configured tinc overlay network.
    # @return [String] e.g. `"10.42.0.0"`
    def tinc_network
      if CloudModel.config.tinc_network
        NetAddr.parse_net(CloudModel.config.tinc_network).network.to_s
      else
        '10.42.0.0'
      end
    end

    # Returns the underlying NetAddr CIDR object for this address.
    # @return [NetAddr::IPv4Net, NetAddr::IPv6Net]
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