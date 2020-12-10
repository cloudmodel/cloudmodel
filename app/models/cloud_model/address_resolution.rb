module CloudModel

  # Handle IP resolution
  class AddressResolution
    require 'netaddr'

    include Mongoid::Document
    include Mongoid::Timestamps

    field :ip, type: String
    field :name, type: String
    field :alt_name, type: Array
    field :active, type: Boolean, default: false
    field :ptr_active, type: Boolean, default: true

    before_validation :check_ip_format
    validates :ip, uniqueness: true
    validates :name, format: {with: /\A([\w-]+\.)*[\w\-]+\.\w{2,10}\z/}

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

    def address
      CloudModel::Address.from_str ip
    end

    def cidr
      address.cidr
    end

    def alt_addresses
      CloudModel::AddressResolution.where(name: name, :ip.ne => ip)
    end

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