require 'net/ping'

module CloudModel
  class Guest    
    require 'resolv'
    require 'securerandom'

    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::AcceptSizeStrings
    include CloudModel::ENumFields
    include CloudModel::ModelHasIssues
    prepend CloudModel::SmartToString
  
    belongs_to :host, class_name: "CloudModel::Host"
    embeds_many :services, class_name: "CloudModel::Services::Base", :cascade_callbacks => true
    embeds_many :lxd_containers, class_name: "CloudModel::LxdContainer", :cascade_callbacks => true
    embeds_many :lxd_custom_volumes, class_name: "CloudModel::LxdCustomVolume", :cascade_callbacks => true
    field :current_lxd_container_id, type: BSON::ObjectId
    has_many :guest_certificates, class_name: "CloudModel::GuestCertificate"
    
    accepts_nested_attributes_for :lxd_custom_volumes, allow_destroy: true
    
    field :name, type: String
    
    field :private_address, type: String
    field :external_address, type: String
    field :mac_address, type: String
    field :external_alt_names, type: Array, default: []
    
    field :root_fs_size, type: Integer, default: 10737418240
    field :memory_size, type: Integer, default: 2147483648
    field :cpu_count, type: Integer, default: 2
    accept_size_strings_for :root_fs_size
    accept_size_strings_for :memory_size
    
    enum_field :deploy_state, values: {
      0x00 => :pending,
      0x01 => :running,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started
    
    field :deploy_last_issue, type: String
    field :deploy_path, type: String

    validates :name, presence: true, uniqueness: { scope: :host }, format: {with: /\A[a-z0-9\-_]+\z/}
    validates :host, presence: true
    validates :private_address, presence: true
    
    before_validation :set_dhcp_private_address, :on => :create
    before_validation :set_mac_address, :on => :create
    before_destroy    :stop
    
    def current_lxd_container
      lxd_containers.where(id: current_lxd_container_id).first
    end

    def available_private_address_collection
      ([private_address] + host.available_private_address_collection - [nil])
    end
    
    def available_external_address_collection
      ([external_address] + host.available_external_address_collection - [nil])
    end
    
    def external_hostname
      @external_hostname ||= external_address.blank? ? '' : CloudModel::Address.from_str(external_address).hostname
    end
    
    def external_alt_names_string
      external_alt_names * ','
    end
    
    def external_alt_names_string=(string)
      self.external_alt_names = string.split(',').map &:strip
    end
    
    def uuid
      SecureRandom.uuid
    end
    
    def random_2_digit_hex
      "%02x" % SecureRandom.random_number(256)
    end
    
    def to_param
      name
    end
    
    def item_issue_chain
      [host, self]
    end
    
    def exec command
      host.exec "/usr/bin/lxc exec #{current_lxd_container.name.shellescape} -- #{command}"
    end
    
    def exec! command, message
      host.exec! "/usr/bin/lxc exec #{current_lxd_container.name.shellescape} -- #{command}", message
    end
    
    def host_root_path
      "/var/lib/lxd/containers/#{current_lxd_container.name}/rootfs/"
    end
    
    def certificates
      ids = guest_certificates.pluck(:certificate_id)
      services.each do |service|
        ids << service.ssl_cert_id if service.respond_to?(:ssl_cert_id) and service.ssl_cert_id
      end
      
      CloudModel::Certificate.where(:id.in => ids)
    end
    
    def has_certificates?
      certificates.count > 0
    end
    
    def has_service_type?(service_type)
      service_type = service_type.to_s unless service_type.is_a? String
      services.select{|s| s._type == service_type}.count > 0
    end
    
    def components_needed
      components = []
      services.each do |service|
        components += service.components_needed
      end
      
      components.uniq.sort{|a,b| a<=>b}
    end
    
    def template_type
      CloudModel::GuestTemplateType.find_or_create_by components: components_needed
    end
    
    def template
      template_type.last_useable(host)
    end
    
    def worker
      CloudModel::GuestWorker.new self
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
    
    def self.deployable
      scoped.where :deploy_state_id.in => deployable_deploy_state_ids
    end
    
    def deploy(options = {})
      unless deployable? or options[:force]
        return false
      end
      
      update_attribute :deploy_state, :pending
      
      begin
        CloudModel::call_rake 'cloudmodel:guest:deploy', host_id: host_id, guest_id: id
      rescue Exception => e
        update_attributes deploy_state: :failed, deploy_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
      end
    end
    
    def deploy!(options={})
      unless deployable? or options[:force]
        return false
      end
      
      worker.deploy options
    end
    
    def redeploy(options = {})
      unless deployable? or options[:force]
        return false
      end
      
      update_attribute :deploy_state, :pending
      
      begin
        CloudModel::call_rake 'cloudmodel:guest:redeploy', host_id: host_id, guest_id: id
      rescue Exception => e
        update_attributes deploy_state: :failed, deploy_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
      end
    end
  
    def redeploy!(options={})
      unless deployable? or options[:force]
        return false
      end
      
      worker.redeploy options
    end
    
    def self.redeploy(ids, options = {})
      criteria = self.where(:id.in => ids.map(&:to_s))      
      valid_ids = criteria.pluck(:_id).map(&:to_s)
      
      return false if valid_ids.empty? and not options[:force]
      
      criteria.update_all deploy_state_id: deploy_state_id_for(:pending)
      
      begin
        CloudModel::call_rake 'cloudmodel:guest:redeploy_many', guest_ids: valid_ids * ' '
      rescue Exception => e
        criteria.update_all deploy_state_id: deploy_state_id_for(:failed), deploy_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
      end
    end
    
    def check_mk_agent
      if Net::Ping::TCP.new(private_address, 6556).ping
        begin
          s = TCPSocket.new private_address, 6556
          result = ''
          while line = s.gets
            result << line
          end
          s.close
        rescue Errno::ECONNREFUSED
          return [false, "Connection refused"]
        end  
        [true, result]
      else
        return [false, "Connection refused"]
      end
    end
    
    def system_info
      if current_lxd_container.blank?
        {'error' => 'No current lxd container for guest'}
      end
      unless Net::Ping::External.new.ping(private_address)
        {'error' => 'No network connect to guest private address'}
      end
      
      success, result = check_mk_agent
      if success
        #puts result
        
        # success, df_result = exec('df -k -T')
        # if success
        #   result.gsub! "<<<df>>>", "<<<df_check_mk>>>"
        #   df_result = df_result.lines
        #   df_result.shift
        #   result += "<<<df>>>\n" + (df_result * "")
        # end
        
        result.gsub! "<<<df>>>", "<<<df_check_mk>>>"
        result.gsub! "<<<df_k>>>", "<<<df>>>"
        
        CloudModel::CheckMkParser.parse result
      else
        {"error" => result}
      end
    end
    
    def mem_usage
      if check_result = monitoring_last_check_result and sys_info = check_result['system'] and mem_info = sys_info['mem']
        total = mem_info['mem_total'].to_i
        available = mem_info['mem_available'].to_i
        100.0 * (total - available) / total
      end
    end
        
    def cpu_usage 
      if check_result = monitoring_last_check_result and sys_info = check_result['system'] and cpu_info = sys_info['cgroup_cpu']
        cpu_info['last_5_minutes_percentage']
      end
    end
    
    def live_lxc_info
      current_lxd_container.try :live_lxc_info
    end
    
    def lxc_info
      current_lxd_container.try :lxc_info
    end
    
    def start(lxd_container = nil)
      unless lxd_container.blank?
        lxd_container_id = if lxd_container.is_a? CloudModel::LxdContainer
          lxd_container.id
        else
          lxd_container
        end
        collection.update_one({_id:  id}, '$set' => { 'current_lxd_container_id': lxd_container_id })
        self.current_lxd_container_id = lxd_container_id
      end
      
      begin
        return current_lxd_container.start
      rescue
        return false
      end
    end
    
    def stop
      begin
        lxd_containers.each do |c|
          c.stop if c.running?
        end
      rescue
        return false
      end
    end
    
    def stop! options = {}
      stop
      timeout = options[:timeout] || 600
      while vm_state != -1 and timeout > 0 do
        sleep 0.1
        timeout -= 1
      end
    end
    
    def fix_lxd_custom_volumes
      fixed_volumes = []
      print "Finding not existing volumes on guest... "
      lxd_custom_volumes.each do |volume|
        unless volume.volume_exists?
          fixed_volumes << volume
        end
      end
      puts '[Done]'
      
      unless fixed_volumes.blank?
        print "Stopping guest #{name}... "
        stop
        puts '[Done]'
        
        print "Mounting container root... "
        host.exec "zfs mount guests/containers/#{current_lxd_container.name}"
        puts '[Done]'
        
        fixed_volumes.each do |volume|
          print "Creating Volume #{volume}... "
          volume.create_volume!
          puts '[Done]'
          
          print "Mounting volume... "
          host.exec "zfs mount guests/custom/#{volume.name}"
          puts '[Done]'
          
          guest_dir = "#{host_root_path}#{volume.mount_point.gsub(/\/$/, '')}"
          
          print "Copying data from guest root to Volume... "
          cmd = "cp -ra #{guest_dir}/. #{volume.host_path.gsub(/\/$/, '')}"
          #puts cmd
          host.exec cmd 
          puts '[Done]'
          
          print "Moving data on guest root to backup folder... "
          host.exec "mv #{guest_dir} #{guest_dir}.backup"
          puts '[Done]'
          
          print "Creating mountpoint on guest root... "
          host.exec "mkdir #{guest_dir}"
          host.exec "chown 100000:100000 #{guest_dir}"
          puts '[Done]'
          
          print "Unmounting volume... "
            host.exec "zfs unmount guests/custom/#{volume.name}"
          puts '[Done]'
                    
          print "Attaching Volume to Guest... "
          current_lxd_container.lxc "storage volume attach default #{volume.name} #{current_lxd_container.name} #{volume.mount_point}"
          puts '[Done]'
        end
        
        print "Unmounting container root... "
        host.exec "zfs unmount guests/containers/#{current_lxd_container.name}"
        puts '[Done]'
        
        print "Starting guest #{name}... "
        success, result = start
        if 
          puts '[Done]'
        else
          puts '[Failed]'
          puts result
        end
      end
    end
    
    def backup
      success = true
      
      # guest_volumes.where(has_backups: true).each do |volume|
      #   Rails.logger.debug "V #{volume.mount_point}: #{success &&= volume.backup}"
      # end

      services.where(has_backups: true).each do |service|
        Rails.logger.debug "S #{service._type}: #{success &&= service.backup}" 
      end      
      
      success
    end
    
    def generate_mac_address
      def format_mac_address_postfix(i)
        "00:16:3e:#{host.mac_address_prefix}:#{i.to_s(16).rjust(2,'0').upcase}"
      end
      
      i=1      
      while(i<2**8 and host.guests.where(mac_address: format_mac_address_postfix(i), :_id.ne => id).count > 0)
        i += 1
      end

      self.mac_address = format_mac_address_postfix(i)
    end
    
    private  
    def set_dhcp_private_address
      self.private_address = host.dhcp_private_address if private_address.blank?
    end
    
    def set_mac_address
      generate_mac_address if mac_address.blank?
    end
  end
end
