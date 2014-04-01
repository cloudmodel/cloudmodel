require 'net/ssh'

module CloudModel
  class Host
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::ENumFields
  
    field :name, type: String
    field :tinc_public_key, type: String

    enum_field :stage, values: {
      0x00 => :pending,
      0x10 => :testing,
      0x30 => :staging,
      0x40 => :production,
    }, default: :pending
    
    enum_field :deploy_state, values: {
      0x00 => :pending,
      0x01 => :running,
      0x02 => :booting,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started
    
    field :deploy_last_issue, type: String
    
    has_many :guests, class_name: "CloudModel::Guest", inverse_of: :host
    embeds_many :addresses, class_name: "CloudModel::Address", inverse_of: :host do
      def << (value)
        if value.class == String
          value = CloudModel::Address.from_str(value)
        elsif value.class == Hash
          value = CloudModel::Address.new(value)
        end
        
        super value
      end
    end
    accepts_nested_attributes_for :addresses, allow_destroy: true
    
    embeds_one :primary_address, class_name: "CloudModel::Address", autobuild: true, inverse_of: :host
    accepts_nested_attributes_for :primary_address  
    
    embeds_one :private_network, class_name: "CloudModel::Address", autobuild: true, inverse_of: :host
    accepts_nested_attributes_for :private_network  
  
    has_many :volume_groups, class_name: "CloudModel::VolumeGroup", inverse_of: :host
    accepts_nested_attributes_for :volume_groups  
    
    validates :name, presence: true, uniqueness: true, format: {with: /\A[a-z0-9\-_]+\z/}
    validates :primary_address, presence: true
    validates :private_network, presence: true    
   
    def default_root_volume_group
      volume_groups.first
    end
    
    def default_data_volume_group
      volume_groups.last
    end
   
    def addresses=(value)
      self.addresses.clear
      value.each do |v|
        self.addresses << v
      end
    end
   
    def primary_address_with_strings=(value)
      if value.class == String
       value = CloudModel::Address.from_str(value)
      end

      self.primary_address_without_strings = value
    end
    alias_method_chain :primary_address=, :strings
    
    def private_network_with_strings=(value)
      if value.class == String
        value = CloudModel::Address.from_str(value)
      end
      
      self.private_network_without_strings = value
    end
    alias_method_chain :private_network=, :strings
  
    def available_private_address_collection
      all = private_network.list_ips - [private_network.gateway]
      used = guests.map{ |g| g.private_address }
      all - used
    end
    
    def available_external_address_collection
      all = addresses.map{ |a| a.list_ips if a.ip_version == 4 }.flatten
      used = guests.map{ |g| g.external_address }
      all - used - [nil]
    end
    
    def dhcp_private_address
      available_private_address_collection.last
    end
    
    def dhcp_external_address
      available_external_address_collection.last
    end
  
    def tinc_private_key
      require 'openssl'
      key = OpenSSL::PKey::RSA.new(2048)
    
      self.update_attributes tinc_public_key: key.public_key.to_s
    
      key
    end
    
    def to_param
      name
    end
    
    def ssh_connection
      @ssh_connection ||= Net::SSH.start(primary_address.ip, "root")
    end
    
    def list_real_volume_groups
      begin
        result = ssh_connection.exec "vgs --separator ';' --units b --all --nosuffix -o vg_all"
        volume_groups = {}
    
        lines = result.split("\n")
        head = lines.shift.split(";").map{|c| c.strip.sub('#', '').gsub(' ', '_').underscore.to_sym}

        lines.each do |row|
          columns = row.split(";")
          row_hash = {}
          head.each do |n|
            row_hash[n] = columns.shift.strip
          end
      
          name = row_hash.delete(:vg).to_sym
          volume_groups[name] = row_hash
        end

        return volume_groups
      rescue
      end
    end
    
    def deployable?
      [:finished, :failed, :not_started].include? deploy_state
    end
    
    def deploy(options = {})
      unless deployable? or options[:force]
        return false
      end
      
      update_attribute :deploy_state, :pending
      
      begin
        CloudModel::call_rake 'cloudmodel:host:deploy', host_id: id
      rescue
        update_attributes deploy_state: :failed, deploy_last_issue: 'Unable to enqueue job! Try again later.'
      end
    end
    
    def redeploy(options = {})
      unless deployable? or options[:force]
        return false
      end
      
      update_attribute :deploy_state, :pending
      
      begin
        CloudModel::call_rake 'cloudmodel:host:redeploy', host_id: id
      rescue
        update_attributes deploy_state: :failed, deploy_last_issue: 'Unable to enqueue job! Try again later.'
      end
    end
  end
end
