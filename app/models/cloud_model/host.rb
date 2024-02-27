require 'net/ssh'
require 'net/sftp'

unless defined?(Zeitwerk)
  require_relative('mixins/e_num_fields')
  require_relative('mixins/has_issues')
  require_relative('mixins/smart_to_string')
end

module CloudModel
  class Host

    module SmartGettersAndSetters
      def cpu_count
       if super < 0
         begin
           success, result = exec 'grep processor.*:\ [0-9] /proc/cpuinfo | wc -l'
           self.cpu_count = result.to_i
         rescue
         end
       end
       super
      end

      def primary_address=(value)
        if value.class == String
         value = CloudModel::Address.from_str(value)
        end

        super value
      end

      def private_network=(value)
        if value.class == String
          value = CloudModel::Address.from_str(value)
        end

        super value
      end
    end

    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::ENumFields
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString
    prepend SmartGettersAndSetters

    field :name, type: String
    field :tinc_public_key, type: String
    field :initial_root_pw, type: String
    field :cpu_name, type: String
    field :cpu_count, type: Integer, default: -1
    field :arch, type: String, default: 'amd64'
    field :mac_address_prefix, type: String
    field :system_disks, type: Array, default: ['sda', 'sdb']
    embeds_many :extra_zpools, class_name: "CloudModel::Zpool", inverse_of: :host
    accepts_nested_attributes_for :extra_zpools, allow_destroy: true

    enum_field :stage, {
      0x00 => :pending,
      0x10 => :testing,
      0x30 => :staging,
      0x40 => :production,
    }, default: :pending

    enum_field :deploy_state, {
      0x00 => :pending,
      0x01 => :running,
      0xe0 => :booting,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    field :deploy_last_issue, type: String
    field :last_deploy_finished_at, type: Time

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

    embeds_many :firewall_rules, class_name: "CloudModel::FirewallRule", inverse_of: :host
    accepts_nested_attributes_for :firewall_rules, allow_destroy: true

    embeds_one :primary_address, class_name: "CloudModel::Address", autobuild: true, inverse_of: :host
    accepts_nested_attributes_for :primary_address

    embeds_one :private_network, class_name: "CloudModel::Address", autobuild: true, inverse_of: :host
    accepts_nested_attributes_for :private_network

    validates :name, presence: true, uniqueness: true, format: {with: /\A[a-z0-9\-_]+\z/}
    validates :primary_address, presence: true
    validates :private_network, presence: true
    validates :mac_address_prefix, presence: true, uniqueness: true

    before_validation :generate_mac_address_prefix

    index _id: 1

    def addresses=(value)
      self.addresses.clear
      value.each do |v|
        self.addresses << v
      end
    end

    def to_param
      name
    end

    def private_address_collection
      private_network.list_ips - [private_network.gateway]
    end

    def available_private_address_collection
      all = private_address_collection
      used = guests.map{ |g| g.private_address }
      all - used
    end

    def external_address_collection
      addresses.map{ |a| a.list_ips if a.ip_version == 4 }.flatten
    end

    def available_external_address_collection
      all = external_address_collection
      used = guests.map{ |g| g.external_address }
      all - used - [nil]
    end

    def external_address_resolutions
      resolutions_v4 = []
      resolutions_v6 = []

      addresses.each do |address|
        if address.ip_version == 6
          resolutions_v6 += CloudModel::AddressResolution.for_subnet(address).to_a
        else
          resolutions_v4 += CloudModel::AddressResolution.for_subnet(address).to_a
        end
      end

      resolutions_v6 = resolutions_v6.flatten.sort{|a,b| a.cidr.cmp b.cidr}
      resolutions_v4 = resolutions_v4.flatten.sort{|a,b| a.cidr.cmp b.cidr}
      resolutions_v4 + resolutions_v6
    end

    def external_address_resolution_hash
      result = {}
      external_address_resolutions.each do |resolution|
        result[resolution.ip] = resolution.name
      end
      result
    end

    def dhcp_private_address
      available_private_address_collection.last
    end

    def dhcp_external_address
      available_external_address_collection.last
    end

    def private_address
      private_network.list_ips.first
    end

    def email_hostname
      hostname = primary_address.hostname

      if hostname == primary_address.ip.to_s or hostname !=~ /.*\..*/
        hostname = "#{name}.#{CloudModel.config.email_domain || 'example.com'}"
      end

      hostname
    end

    def name_with_stage
      "[#{stage}] #{name}"
    end

    def self.update_tinc_keys
      CloudModel::Host.each do |host|
        begin
          host.worker.update_tinc_host_files
          puts "Updated keys on #{host.name}"
        rescue
          puts "Failed to update for #{host.name}"
        end
      end
    end

    def tinc_private_key
      require 'openssl'
      key = OpenSSL::PKey::RSA.new(2048)

      self.update_attributes tinc_public_key: key.public_key.to_s

      key
    end

    def ssh_connection
      @ssh_connection ||= if initial_root_pw
        Net::SSH.start(primary_address.ip, "root",
          password: initial_root_pw,
          verify_host_key: :never
        )
      else
        host_ip = if CloudModel.config.use_external_ip
          primary_address.ip
        else
          private_network.list_ips.first
        end

        begin
          Net::SSH.start(host_ip, "root",
            keys: ["#{CloudModel.config.data_directory}/keys/id_rsa"],
            keys_only: true,
            password: ''
          )
        rescue Errno::EHOSTUNREACH, Errno::ETIMEDOUT, Errno::ENETUNREACH
          # If not reachable via VPN, try external IP
          Net::SSH.start(primary_address.ip, "root",
            keys: ["#{CloudModel.config.data_directory}/keys/id_rsa"],
            keys_only: true,
            password: ''
          )
        end
      end
    end

    def sftp
      ssh_connection.sftp
    end

    def ssh_address
      ssh_connection.host
      #initial_root_pw ? primary_address.ip : private_address
    end

    def shell
      puts "ssh -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa root@#{ssh_address}"
    end

    def sync_inst_images
      if CloudModel.config.skip_sync_images
        return true
      end

      # TODO: make work with initial root pw
      command = "rsync -avz -e 'ssh -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa' #{CloudModel.config.data_directory.shellescape}/cloud/ root@#{ssh_address}:/cloud"
      Rails.logger.debug command
      `#{command}`
    end

    def exec command
      Rails.logger.debug "EXEC: #{command}"

      stdout_data = ''
      stderr_data = {}
      exit_status = nil
      exit_signal = nil
      #puts command

      # Close SFTP channel as it would break the ssh loop
      sftp.close_channel
      ssh_connection.instance_variable_set('@sftp', nil)

      ssh_connection.open_channel do |channel|
        channel.exec(command) do |ch, success|
          unless success
            abort "FAILED: couldn't execute command (ssh.channel.exec)"
          end
          channel.on_data do |ch,data|
            Rails.logger.debug "  STDOUT: #{data}"
            stdout_data += data
          end

          channel.on_extended_data do |ch,type,data|
            Rails.logger.debug "  STDERR: (#{type}): #{data}"
            stderr_data[type] ||= ''
            stderr_data[type] += data
          end

          channel.on_request("exit-status") do |ch,data|
            exit_status = data.read_long
            Rails.logger.debug "  exit-status: #{exit_status}"
          end

          channel.on_request("exit-signal") do |ch, data|
            exit_signal = data.read_long
            Rails.logger.debug "  exit-signal: #{exit_signal}"
          end
        end
      end
      ssh_connection.loop

      success = exit_status == 0
      Rails.logger.debug [success, stdout_data, stderr_data, exit_status, exit_signal]

      stdout = stdout_data
      unless success
        stdout += "\n\n" + stderr_data.values * "\n"
      end

      return [success, stdout]
    end

    def exec! command, message
      success, data = exec command

      unless success
        raise "#{message}:\n\n#{data}"
      end
      data
    end

    def mounted_at? mountpoint, root=''
      if exec('mount')[1].match(/on #{root.gsub(/[\/]$/, '')}\/#{mountpoint.gsub(/^[\/]/, '')} type/)
        true
      else
        false
      end
    end

    def boot_fs_mounted? root=''
      mounted_at? '/boot', root
    end

    def mount_boot_fs root=''
      # Don't mount /boot if already mounted!
      if boot_fs_mounted? root
        return true
      else
        success, data = exec "mkdir -p #{root}/boot && mount /dev/md0 #{root}/boot"
        unless success
          success, data = exec "mount /dev/md/rescue:0 #{root}/boot"
        end

        return success
      end
    end

    def unmount_boot_fs root=''
      success, data = exec "umount #{root}/boot"

      return success
    end

    def cpu_name
      if super.blank?
        unless Net::Ping::External.new.ping(private_network.list_ips.first)
          'No network connect to host private address'
        end

        success, result = exec('cat /proc/cpuinfo')
        if success
          name = result.lines.select{|l| l =~ /model name/}.first.split(':')[1].strip
          update_attribute :cpu_name, name
          name
        else
          "Unknown"
        end
      else
        super
      end
    end

    def system_info
      unless Net::Ping::External.new.ping(private_network.list_ips.first)
        {'error' => 'No network connect to host private address'}
      end

      success, result = exec('check_mk_agent')
      if success
        success, df_result = exec('df -k -T')
        if success
          result.gsub! "<<<df>>>", "<<<df_check_mk>>>"
          df_result = df_result.lines
          df_result.shift
          result += "<<<df>>>\n" + (df_result * "")
        end
        CloudModel::CheckMkParser.parse result
      else
        {'error' => result}
      end
    end

    def live_lxc_info
      begin
        success, result = exec('lxc list --format yaml')
        if success
          result = YAML.load(result, permitted_classes: [Symbol, Time])

          result ||= []
          info = {}

          result.each do |c|
            info[c.delete('name')] = c
          end

          info
        else
          {}
        end
      rescue
        {}
      end
    end

    def memory_size
      if check_result = monitoring_last_check_result and sys_info = check_result['system'] and mem_info = sys_info['mem']
        mem_info['mem_total'].to_i * 1024
      end
    end

    def mem_usage
      if check_result = monitoring_last_check_result and sys_info = check_result['system'] and mem_info = sys_info['mem']
        total = memory_size
        available = mem_info['mem_available'].to_i * 1024
        100.0 * (total - available) / total
      end
    end

    def cpu_usage
      if check_result = monitoring_last_check_result and sys_info = check_result['system'] and cpu_info = sys_info['cgroup_cpu']
        cpu_info['last_5_minutes_percentage']
      end
    end

    def deployable?
      [:finished, :failed, :not_started].include? deploy_state
    end

    def worker
      CloudModel::Workers::HostWorker.new self
    end

    def deploy(options = {})
      unless deployable? or options[:force]
        return false
      end

      update_attribute :deploy_state, :pending

      begin
        CloudModel::HostJobs::DeployJob.perform_later id.to_s
      rescue Exception => e
        update_attributes deploy_state: :failed, deploy_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
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
        CloudModel::HostJobs::RedeployJob.perform_later id.to_s
      rescue Exception => e
        update_attributes deploy_state: :failed, deploy_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    def redeploy!(options={})
      unless deployable? or options[:force]
        return false
      end

      worker.redeploy options
    end

    def restart_firewall
      CloudModel::Workers::FirewallWorker.new(self).write_scripts
      exec! "/etc/cloud_model/firewall_stop && /etc/cloud_model/firewall_start", "Failed to restart Firewall!"
    end

    def generate_mac_address_prefix
      def format_mac_address_prefix(i)
        i.to_s(16).rjust(4,'0').upcase.scan(/.{1,2}/) * ':'
      end
      i = CloudModel.config.host_mac_address_prefix_init.gsub(':', '').hex

      while(i<2**16 and CloudModel::Host.where(mac_address_prefix: format_mac_address_prefix(i), :_id.ne => id).count > 0)
        i += 1
      end

      self.mac_address_prefix = format_mac_address_prefix(i)
    end

    private
    def set_mac_address_prefix
      generate_mac_address_prefix if mac_address_prefix.blank?
    end
  end
end
