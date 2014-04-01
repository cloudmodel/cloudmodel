module CloudModel
  class Guest    
    require 'resolv'
    require 'securerandom'

    include Mongoid::Document
    include Mongoid::Timestamps
    
    include CloudModel::AcceptSizeStrings
    include CloudModel::ENumFields
  
    belongs_to :host, class_name: "CloudModel::Host"
    embeds_many :services, class_name: "CloudModel::Services::Base"
    has_one :root_volume, class_name: "CloudModel::LogicalVolume", inverse_of: :guest, autobuild: true
    accepts_nested_attributes_for :root_volume
    has_many :guest_volumes, class_name: "CloudModel::GuestVolume"
    accepts_nested_attributes_for :guest_volumes, allow_destroy: true
    
    field :name, type: String
    
    field :private_address, type: String
    field :external_address, type: String
    field :external_hostname, type: String
    
    field :memory_size, type: Integer, default: 2147483648
    field :cpu_count, type: Integer, default: 2
    
    enum_field :deploy_state, values: {
      0x00 => :pending,
      0x01 => :running,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started
    
    field :deploy_last_issue, type: String
    
    accept_size_strings_for :memory_size
      
    validates :name, presence: true, uniqueness: { scope: :host }, format: {with: /\A[a-z0-9\-_]+\z/}
    validates :host, presence: true
    validates :root_volume, presence: true
    validates :private_address, presence: true
    
    attr_accessor :deploy_path, :deploy_volume
    
    before_validation :set_root_volume_name
    #after_save :deploy
    
    STATES = {
      -1 => :undefined,
      0 => :no_state,
      1 => :running,
      2	=> :blocked,
      3 => :paused,
      4 => :shutdown,
      5 => :shutoff,
      6 => :crashed,
      7 => :suspended
    }
   
    def state_to_id state
      STATES.invert[state.to_sym] || -1
    end
    
    def base_path
      "/vm/#{name}"
    end
    
    def deploy_volume
      @deploy_volume ||= root_volume
    end
    
    def deploy_path
      @deploy_path ||= base_path
    end
   
    def config_root_path
      "#{base_path}/etc"
    end

    def available_private_address_collection
      ([private_address] + host.available_private_address_collection - [nil])
    end
    
    def available_external_address_collection
      ([external_address] + host.available_external_address_collection - [nil])
    end
    
    def external_hostname
      self[:external_hostname] ||= begin
        Resolv.getname(external_address)
      rescue
        external_address
      end
    end
    
    def uuid
      SecureRandom.uuid
    end
    
    def random_2_digit_hex
      "%02x" % SecureRandom.random_number(256)
    end
    
    def mac_address
      "52:54:00:#{random_2_digit_hex}:#{random_2_digit_hex}:#{random_2_digit_hex}"
    end
    
    def to_param
      name
    end
    
    def virsh cmd, options = []
      option_string = ''
      options = [options] if options.is_a? String
      options.each do |option|
        option_string = "#{option_string}--#{option.shellescape} "
      end
      host.ssh_connection.exec("/usr/bin/virsh #{cmd.shellescape} #{option_string}#{name.shellescape}")
    end 
    
    def self.deploy_state_id_for deploy_state
      enum_fields[:deploy_state][:values].invert[deploy_state]
    end
    
    def self.deployable_deploy_states
      [:finished, :failed, :not_started]
    end
    
    def self.deployable_deploy_state_ids
      deployable_deploy_states.map{|s| deploy_state_id_for s}
    end
    
    def deployable?
      self.class.deployable_deploy_states.include? deploy_state
    end
    
    def self.deployable?
      where :deploy_state_id.in => deployable_deploy_state_ids
    end
    
    def deploy(options = {})
      unless deployable? or options[:force]
        return false
      end
      
      update_attribute :deploy_state, :pending
      
      begin
        CloudModel::call_rake 'cloudmodel:guest:deploy', host_id: host_id, guest_id: id
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
        CloudModel::call_rake 'cloudmodel:guest:redeploy', host_id: host_id, guest_id: id
      rescue
        update_attributes deploy_state: :failed, deploy_last_issue: 'Unable to enqueue job! Try again later.'
      end
    end
  
    def self.redeploy(ids, options = {})
      criteria = self.where(:id.in => ids.map(&:to_s))      
      valid_ids = criteria.pluck(:_id).map(&:to_s)
      
      return false if valid_ids.empty? and not options[:force]
      
      criteria.update_all deploy_state_id: deploy_state_id_for(:pending)
      
      begin
        CloudModel::call_rake 'cloudmodel:guest:redeploy_many', guest_ids: valid_ids
      rescue
        criteria.update_all deploy_state_id: deploy_state_id_for(:failed), deploy_last_issue: 'Unable to enqueue job! Try again later.'
      end
    end
    
    def state
      @real_state unless @real_state.blank?
      begin
        @real_state = state_to_id virsh('domstate').strip
      rescue
        -1
      end
    end
    
    def vm_info
      @real_vm_info unless @real_vm_info.blank?
      begin
        vm_info={}
        res = virsh('dominfo')
    
        res.lines.each do |line|
          k,v = line.split(':')
          vm_info[k.gsub(' ', '_').underscore] = v.try(:strip)
        end
    
        vm_info['memory']  = vm_info.delete('used_memory').to_i * 1024
        vm_info['max_mem'] = vm_info.delete('max_memory').to_i * 1024
        vm_info['state']   = state_to_id(vm_info['state'])
        vm_info['cpus']    = vm_info.delete("cpu(s)").to_i
        vm_info['active']  = (vm_info['state'] == 1)
        
        vm_info
      rescue
        {"state" => -1}
      end
    end
    
    def start
      begin
        virsh 'autostart'
        virsh 'start'
        return true
      rescue
        return false
      end
    end
    
    def stop
      begin
        virsh 'shutdown'
        virsh 'autostart', 'disable'
        return true
      rescue
        return false
      end
    end
    
    private  
    def set_root_volume_name
      root_volume.name = "#{name}-root-#{Time.now.strftime "%Y%m%d%H%M%S"}" unless root_volume.name
    end
  end
end