module CloudModel

  # Maps an IP address to a hostname, acting as an internal DNS registry.
  #
  # Used by {Address#hostname} and {Address#list_ips} (for IPv6 subnets) to
  # resolve IPs without relying on public reverse DNS. Each record is unique
  # per IP.
  class AddressResolution
    require 'netaddr'

    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [rw] ip
    #   @return [String] the IP address being resolved
    field :ip, type: String

    # @!attribute [rw] name
    #   @return [String] the primary hostname for this IP (FQDN)
    field :name, type: String

    # @!attribute [rw] alt_names
    #   @return [Array<String>] additional hostnames (SAN / CNAME targets)
    field :alt_names, type: Array

    # @!attribute [rw] active
    #   @return [Boolean] whether a forward DNS record should be published
    field :active, type: Boolean, default: false

    # @!attribute [rw] ptr_active
    #   @return [Boolean] whether a PTR reverse-DNS record should be published
    field :ptr_active, type: Boolean, default: true

    before_validation :check_ip_format
    validates :ip, uniqueness: true
    validates :name, format: {with: /\A([\w-]+\.)*[\w\-]+\.\w{2,10}\z/}

    # Returns AddressResolution records for all IPs in a subnet.
    #
    # For IPv4 subnets, initializes (but does not save) records for every
    # address in the range. For IPv6, queries by prefix match.
    #
    # @param subnet [CloudModel::Address, String] the subnet to query
    # @return [Array<CloudModel::AddressResolution>]
    def self.for_subnet(subnet)
      subnet = CloudModel::Address.from_str subnet if subnet.is_a? String
      if subnet.ip_version == 4
        resolutions = []
        subnet.list_ips(include_network:true, include_gateway:true).each do |ip|
          resolutions << find_or_initialize_by(ip:ip)
        end
        resolutions
      else
        where(ip: /^#{subnet.ip.to_s}/)
      end
    end

    # Returns an {Address} object wrapping this record's IP.
    # @return [CloudModel::Address]
    def address
      CloudModel::Address.from_str ip
    end

    # Returns the NetAddr CIDR object for this IP.
    # @return [NetAddr::IPv4Net, NetAddr::IPv6Net]
    def cidr
      address.cidr
    end

    # Returns other AddressResolution records that share the same hostname.
    # @return [Mongoid::Criteria<CloudModel::AddressResolution>]
    def alt_addresses
      CloudModel::AddressResolution.where(name: name, :ip.ne => ip)
    end

    # Returns the IP addresses of other records sharing the same hostname.
    # @return [Array<String>]
    def alt_ips
      alt_addresses.map(&:ip)
    end

    private
    def check_ip_format
      if ip =~ /^[0-9a-f\.\:]+$/
        begin
          a = address
        rescue
          errors.add :ip, :invalid
        end
      else
        errors.add :ip, :invalid
      end
    end
  end
end