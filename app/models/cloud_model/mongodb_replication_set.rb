module CloudModel
  def self.mongodb_version_path
    ["3.2", "3.4", "3.6", "4.0", "4.2", "4.4", "5.0", "6.0", "7.0", "8.0", "8.2"]
  end

  # Manages a MongoDB replica set across multiple {Services::Mongodb} instances.
  #
  # After creating and configuring the member services, call {#initiate} once to
  # bootstrap the replica set. Subsequent membership changes are handled via
  # {#reconfig}. The {#status} method reflects the live replica set state
  # returned by `replSetGetStatus`.
  class MongodbReplicationSet
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] name
    #   @return [String] replica set name (used in MongoDB config as `_id`)
    field :name, type: String

    # @!attribute [rw] initiated
    #   @return [Boolean] true once `rs.initiate()` has been run successfully
    field :initiated, type: Boolean, default: false

    # @!attribute [rw] active
    #   @return [Boolean, nil] whether the replica set is currently considered active
    field :active, type: Boolean

    # @return [Mongoid::Criteria<CloudModel::Guest>] guests running a member service
    def guests
      CloudModel::Guest.where("services.mongodb_replication_set_id" => id)
    end

    # @return [Array<CloudModel::Services::Mongodb>] all member services
    def services
      guests.map{ |guest|
        guest.services.where(mongodb_replication_set_id: id).to_a
      }.flatten
    end

    # Adds a MongoDB service to this replica set.
    # @param service [CloudModel::Services::Mongodb]
    def add_service service
      service.update_attribute :mongodb_replication_set_id, id
    end

    # Reads the current `featureCompatibilityVersion` from the live replica set.
    # @return [String, nil] e.g. `"6.0"`, or nil if unreachable
    def feature_compatibility_version
      begin
        db_command(getParameter: 1, featureCompatibilityVersion: 1).first['featureCompatibilityVersion']['version']
      rescue
      end
    end

    # Builds the `rs.initiate()` JavaScript command string for this replica set.
    # @return [String]
    def init_rs_cmd
      cmd = "rs.initiate( {\n" +
            "   _id : \"#{name}\",\n" +
            "   members: [\n"

      services.each_with_index do |service,i|
        cmd += "      { _id: #{i}, host: \"#{service.private_address}:#{service.port}\", arbiterOnly: #{service.mongodb_replication_arbiter_only}, priority: #{service.mongodb_replication_priority} },\n"
      end

      cmd += "   ]\n" +
             "})\n"

      cmd
    end

    # @return [Array<String>] MongoDB URIs for all member services
    def service_uris
      services.map do |service|
        service.server_uri
      end
    end

    # @return [Array<String>] URIs for services not in a `:critical` monitoring state
    def operational_service_uris
      services.map do |service|
        service.server_uri if service.state != :critical
      end - [nil]
    end

    # Returns a live Mongo::Client connected to the operational members, or false/nil
    # when the set is uninitiated or all members are down.
    # @return [Mongo::Client, false, nil]
    def client
      if initiated? and operational_service_uris.first
        begin
          Mongo::Client.new(operational_service_uris, connect_timeout: 1, server_selection_timeout: 1)
        rescue
          false
        end
      else
        nil
      end
    end

    # Runs a MongoDB admin command and returns the result documents.
    # @param command [Hash] the command hash, e.g. `{ replSetGetStatus: true }`
    # @return [Array<Hash>, nil]
    def db_command command
      if c = client
        begin
          c.database.command(command).documents
        rescue Exception => e
          [{'retval' => {error: "Can´t execute #{command}"}, 'exception' => e.to_s}]
        ensure
          c.close
        end
      end
    end

    # def eval js
    #   if res = db_command(eval: js)
    #     res.first['retval']
    #   else
    #     false
    #   end
    # end

    # Bootstraps the replica set by running `rs.initiate()` on the first guest.
    # Sets {#initiated} to true on success and triggers a monitoring check.
    # @return [Array(Boolean, String)] `[success, output]`
    def initiate
      if guests.blank?
        return false, 'No guests found'
      end
      ret, msg = guests.first.exec "mongosh --quiet --eval #{init_rs_cmd.shellescape}"
      if ret
        ret = false if msg =~ /"ok"\s\:\s0/
        update_attribute :initiated, true if ret
        CloudModel::Monitoring::MongodbReplicationSetChecks.new(self).check
      end
      return ret, msg
    end

    # Returns the live replica set status merged with service metadata.
    # @param options [Hash]
    # @option options [Boolean] :service_id_only replace service objects with their IDs
    # @return [Hash]
    def status options={}
      data = db_command(replSetGetStatus: true).try :first
      data ||= {}
      data['members'] ||= []

      services.each do |service|
        member = data['members'].find{|member| member['name'] == service.server_uri}

        if member
          member['found'] = true
          member['service'] = service
        else
          data['members'] << {
            '_id' => nil,
            'name' => service.server_uri,
            'found' => false,
            'service' => service,
            'state' => -1,
            'stateStr' => 'N/C'
          }
        end
      end

      data['clusterTime'] = data.delete('$clusterTime')

      if options[:service_id_only]
        data['members'] = data['members'].map do |member|
          if member['service']
            member['host_id'] = member['service'].guest.host_id
            member['guest_id'] = member['service'].guest.id
            member['service_id'] = member.delete('service').id
            member
          end
        end
      end

      data
    end

    def read_config
      config = db_command(replSetGetConfig: true, commitmentStatus: true)
      if config.first['exception']
        raise RuntimeError, "#{config.first['retval'][:error]}\n\n#{config.first['exception']}"
      end
      unless config.first['commitmentStatus']
        raise RuntimeError, "Previous reconfig has not been committed yet"
      end
      config.first['config']
    end

    # Reconciles the live replica set configuration with the current service list,
    # adding missing members and updating priorities. Handles the arbiter-only
    # constraint by calling itself recursively when that setting changes.
    # @return [Array<Hash>] result documents from `replSetReconfig`
    def reconfig
      begin
        config = read_config
      rescue Exception => e
        puts e
        initiate
        config = read_config
      end

      new_members = []
      max_member_id = config['members'].map{|m| m['_id']}.max
      has_changed_arbiter_setting_on_member = false

      services.each do |service|
        member = config['members'].find{|m| m['host'] == service.server_uri} || {
          '_id' => (max_member_id += 1),
          'host' => service.server_uri,
          'arbiterOnly' => service.mongodb_replication_arbiter_only
        }

        member['priority'] = service.mongodb_replication_priority

        # Increase id if arbiterOnly did change from previous config
        if not member['arbiterOnly'].nil? and member['arbiterOnly'] != service.mongodb_replication_arbiter_only
          puts "#{service} on #{service.guest} changed arbiter to #{member['arbiterOnly']}"
          has_changed_arbiter_setting_on_member = true
        else
          new_members << member
        end
      end

      config['version'] += 1
      config['members'] = new_members

      res = db_command replSetReconfig: config

      if has_changed_arbiter_setting_on_member and res.first['ok']
        puts 'Reconfig again to change arbiter setting...'
        return reconfig
      end

      res
    end


    # def add host
    #   eval "rs.add('#{host}')"
    # end
    #
    # def remove host
    #   eval "rs.remove('#{host}')"
    # end

    # Steps the `featureCompatibilityVersion` up to `version` one step at a time,
    # redeploying services as needed to match the required MongoDB binary version.
    # @param version [String] target FCV, e.g. `"7.0"`
    # @param options [Hash]
    # @option options [Boolean] :debug verbose logging
    # @return [Boolean] false if already at target or upgrade is impossible
    def update_feature_compatibility_version! version, options={}
      unless CloudModel::mongodb_version_path.index(version)
        puts "Version #{version} is not in the allowed versions (#{CloudModel::mongodb_version_path * ', '})"
        return false
      end

      if services.blank?
        puts "No services found"
        return false
      end

      features = feature_compatibility_version

      if version == features
        puts "Already on requested feature level #{version}"
        return false
      end
      if version < features
        puts "You can not downgrade a replication set (#{features} => #{version})"
        return false
      end

      if latest_compatible_version = CloudModel::mongodb_version_path[CloudModel::mongodb_version_path.index(features) + 1]
        puts "# Check if version of current services is #{latest_compatible_version}"
        deployed = false
        # ensure all guests are up to there set mongo version
        services.each do |service|
          unless current_version = service.service_status['version']
            puts "Service #{service.name} on guest #{service.guest.host.name}:#{service.guest.name} not running?"
          end
          service.update_attribute :mongodb_version, latest_compatible_version
          if service.mongodb_version > current_version
            puts "### Service #{service.name} on guest #{service.guest.host.name}:#{service.guest.name} needs updating (#{current_version} => #{service.mongodb_version})"
            service.guest.redeploy! force: true, debug: options[:debug]
            deployed = true
          end
        end
        if deployed
          puts "# Waiting for service to restart"
          sleep 60
        end
        puts "# Set Feature Compatibility Version to #{latest_compatible_version}"
        puts db_command(setFeatureCompatibilityVersion: latest_compatible_version)
      else
        puts "There is no newer version available as the current compatibility version (#{features})"
        return false
      end

      if latest_compatible_version < version
        #next_version = CloudModel::mongodb_version_path[CloudModel::mongodb_version_path.index(latest_compatible_version) + 1]
        update_feature_compatibility_version! version, options
      end
      true
    end

  end
end