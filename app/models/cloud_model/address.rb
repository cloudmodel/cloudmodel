module CloudModel
  class Address
    require 'netaddr'

    include Mongoid::Document
    include Mongoid::Timestamps
    
    embedded_in :host, :polymorphic => true
  
    field :ip, type: String
    field :subnet, type: Integer
    field :gateway, type: String
    field :hostname, type: String
    
    validates :ip, presence: true
    validates :subnet, presence: true
    
    validate :check_ip_format
   
    # def initialize(options = {})
    #   if options.class == String
    #     self.from_string options
    #   else
    #     super
    #   end
    # end
   
    def self.from_str(str)
      net = ::NetAddr.parse_net(str)
      ip = ::NetAddr.parse_ip(str.split(/[\/ ]/).first)
      
      self.new ip: ip.to_s, subnet: net.netmask.to_s.gsub(/^\//, '')
    end
   
    def to_s options={}
      if ip and subnet
        "#{ip}/#{subnet}"
      else
        ""
      end
    end
   
    def hostname
      self[:hostname] ||= begin
        Resolv.getname(ip)
      rescue
        ip
      end
    end
       
    def network
      cidr.network.to_s
    end
    
    def netmask
      if ip_version == 4
        cidr.netmask.extended
      else
        cidr.netmask.to_s
      end
    end
    
    def broadcast
      cidr.nth(cidr.len - 1).to_s if ip_version == 4
    end
    
    def ip_version
      cidr.version
    end
    
    def range?
      ip == network
    end
    
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

    def tinc_subnet
      16
    end    
    
    def tinc_network
      NetAddr.parse_net("#{CloudModel::Host.last.private_network.ip}/#{tinc_subnet}").network.to_s
    end
        
    private
    def check_ip_format
      begin
        ::NetAddr.parse_net("#{ip}/#{subnet}")
      rescue Exception => e
        self.errors.add(:subnet, :format, default: e.message)
        return false
      end
    end
    
    private
    def cidr
      if subnet
        ::NetAddr.parse_net("#{ip}/#{subnet}")
      else
        ::NetAddr.parse_net(ip)
      end
    end
    
  end
end