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
    # Hostname of the address
    field :hostname, type: String
    
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
      self[:hostname] ||= begin
        Resolv.getname(ip)
      rescue
        ip
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
    
    # Get array of all IPv4 addresses in address block
    def list_ips
      return [] if ip_version==6 # Don't list ips for IPV6
      if range?
        ips = []
        (cidr.len - 2).times do |i|
          ips << cidr.nth(i + 1).to_s
        end
        ips
        #cidr.to_a#.enumerate[1..-2]
      else
        [ip]
      end
    end

    # Get tinc subnet bitmask
    def tinc_subnet
      16
    end    
    
    # Get tinc network
    def tinc_network
      NetAddr.parse_net("#{CloudModel::Host.last.private_network.ip}/#{tinc_subnet}").network.to_s
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
    
    private
    # get NetAddr object
    def cidr
      if subnet
        ::NetAddr.parse_net("#{ip}/#{subnet}")
      else
        ::NetAddr.parse_net(ip)
      end
    end
    
  end
end