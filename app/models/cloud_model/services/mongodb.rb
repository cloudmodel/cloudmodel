module CloudModel
  module Services
    # MongoDB database service embedded in a {Guest}.
    #
    # Supports standalone and replica-set configurations. When assigned to a
    # {MongodbReplicationSet}, the `mongodb_replication_priority` and
    # `mongodb_replication_arbiter_only` fields control this node's role within
    # the set. Backups use `mongodump --gzip`.
    class Mongodb < Base
      # @!attribute [rw] port
      #   @return [Integer] MongoDB listen port (default: 27017)
      field :port, type: Integer, default: 27017

      # @!attribute [rw] mongodb_version
      #   @return [String] MongoDB version to install, e.g. `"6.0"` (default: `"5.0"`)
      field :mongodb_version, type: String, default: '5.0'

      # @!attribute [rw] mongodb_replication_priority
      #   @return [Integer] replica-set election priority (0–100; 0 = never elected)
      field :mongodb_replication_priority, type: Integer, default: 50

      # @!attribute [rw] mongodb_replication_arbiter_only
      #   @return [Boolean] when true, this node is an arbiter and gets priority 0
      field :mongodb_replication_arbiter_only, type: Boolean, default: false

      # @!attribute [rw] mongodb_replication_set
      #   @return [CloudModel::MongodbReplicationSet, nil] the replica set this node belongs to
      belongs_to :mongodb_replication_set, class_name: "CloudModel::MongodbReplicationSet", optional: true

      # @!attribute [rw] mongodb_backup_exclude_collection_prefixes
      #   @return [Array<String>] collection-name prefixes to skip in the
      #     per-service mongodump backup (standalone members only; replica sets
      #     take their excludes from the associated WebImage)
      field :mongodb_backup_exclude_collection_prefixes, type: Array, default: []

      # Accept a whitespace/comma-separated string from forms as well as an array.
      def mongodb_backup_exclude_collection_prefixes=(value)
        value = value.split(/[\s,]+/) if value.is_a?(String)
        super(Array(value).map { |v| v.to_s.strip }.reject(&:blank?))
      end

      validates :mongodb_replication_priority, inclusion: {in: 0..100}

      # Replica-set members are backed up ONCE at the set level, so enabling
      # backups on a member toggles the set instead; the member stores/reports
      # false. Standalone members back up per service via mongodump.
      def has_backups
        if mongodb_replication_set
          !!mongodb_replication_set.has_backups
        else
          super
        end
      end

      def has_backups=(state)
        if rs = mongodb_replication_set
          self[:has_backups] = false
          rs.has_backups = state
          rs.save if rs.persisted? && rs.changed?
        else
          super
        end
      end

      def kind
        :mongodb
      end

      def components_needed
        (["mongodb@#{mongodb_version}".to_sym] + super).uniq
      end

      def sanitize_service_data data
        data.keys.each do |k|
          if k =~ /^\$/
            new_k = k.gsub(/^\$/, '')
            data[new_k] = data.delete k
            k = new_k
          end

          v = data[k]
          if v.is_a? Hash
            data[k] = sanitize_service_data data[k]
          end
        end
        data
      end

      def service_status
        begin
          mongo_client = Mongo::Client.new(["#{server_uri}"], connect_timeout: 1, server_selection_timeout: 1, connect: :direct)
          data = mongo_client.database.command('serverStatus' => true).first
          data['featureCompatibilityVersion'] = mongo_client.database.command(getParameter: 1, featureCompatibilityVersion: 1).first['featureCompatibilityVersion']['version']
        rescue Mongo::Error::NoServerAvailable => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        rescue Exception => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :warning}
        ensure
          mongo_client&.close
        end

        # Remove keys containing config details and doubled values
        %w(host process pid uptimeMillis uptimeEstimate localTime ).each do |k|
          data.delete(k)
        end

        begin
          data['backgroundFlushing'].delete('last_finished')
        rescue
        end

        sanitize_service_data data.as_json
      end

      def server_uri
        "#{private_address}:#{port}"
      end

      def mongodb_replication_priority
        # Make sure it sets priority to 0 if it is arbiter only
        if mongodb_replication_arbiter_only
          0
        else
          super
        end
      end

      def mongodb_replication_set_master?
        if monitoring_last_check_result and monitoring_last_check_result['repl'] and monitoring_last_check_result['repl']['primary']
          monitoring_last_check_result['repl']['primary'] == "#{guest.private_address}:#{port}"
        else
          nil
        end
      end

      def mongodb_replication_set_version
        if monitoring_last_check_result and monitoring_last_check_result['repl']
          monitoring_last_check_result['repl']['setVersion']
        else
          # Not available via monitoring for some reasons
          "-"
        end
      end

      def backupable?
        true
      end

      # MongoDB's data (and journal) live here; this is the dataset that the ZFS
      # volume backup snapshots, so it pairs this service with that volume.
      def backup_data_mount_point
        'var/lib/mongodb'
      end

      # Flush and lock writes around a filesystem snapshot, then unlock. The
      # atomic ZFS snapshot is already crash-consistent (journal on the same
      # dataset); this is belt-and-suspenders to get a checkpoint-clean image.
      # The lock is held only for the (near-instant) snapshot. Best run against
      # a secondary.
      def with_backup_consistency
        client = Mongo::Client.new(
          [server_uri], connect_timeout: 5, server_selection_timeout: 5, connect: :direct
        )
        client.use(:admin).database.command(fsync: 1, lock: true)
        begin
          yield
        ensure
          client.use(:admin).database.command(fsyncUnlock: 1)
        end
      ensure
        client&.close
      end

      def backup
        return false unless has_backups
        # Replica-set members are dumped once at the set level, not per member.
        return false if mongodb_replication_set

        timestamp = Time.now.strftime "%Y%m%d%H%M%S"
        target = "#{backup_directory}/#{timestamp}"
        FileUtils.mkdir_p backup_directory

        if run_mongodump target
          FileUtils.rm_f "#{backup_directory}/latest"
          FileUtils.ln_s target, "#{backup_directory}/latest"
          cleanup_backups

          true
        else
          FileUtils.rm_rf target
          false
        end
      end

      # Restore a dump back into this standalone member. `mongorestore --drop`
      # drops each collection before reloading it, destroying current data, so
      # this is guarded by `force:` to prevent an accidental console trigger.
      # @param timestamp [String] 'latest' or a 14-digit backup timestamp
      # @param force [Boolean] must be true to acknowledge the destructive --drop
      def restore timestamp='latest', force: false
        unless force
          raise CloudModel::BackupError,
            "Refusing to restore mongodb #{name}: `mongorestore --drop` " \
            "destroys current collections. Pass force: true to proceed."
        end

        source = "#{backup_directory}/#{timestamp}"
        if File.exist? source
          command = "LC_ALL=C mongorestore --drop -h #{guest.private_address.shellescape} --port #{port.to_i} #{source.shellescape}"

          Rails.logger.debug command
          Rails.logger.debug `#{command}`

          return $?.success?
        else
          return false
        end
      end

      private

      # Run mongodump for this (standalone) member. With configured exclusion
      # prefixes, dump each database separately (mongodump's exclusion flags
      # require --db); otherwise dump the whole node.
      # @return [Boolean]
      def run_mongodump target
        base = "LC_ALL=C mongodump --gzip -h #{guest.private_address.shellescape} --port #{port.to_i}"

        prefixes = mongodb_backup_exclude_collection_prefixes
        if prefixes.blank?
          return run_command "#{base} -o #{target.shellescape}"
        end

        exclude = prefixes.map { |p| "--excludeCollectionsWithPrefix=#{p.shellescape}" }.join(' ')
        dbs = backup_databases
        return false if dbs.blank?
        dbs.all? do |db|
          run_command "#{base} --db #{db.shellescape} #{exclude} -o #{target.shellescape}"
        end
      end

      # Names of the non-system databases on this member.
      # @return [Array<String>]
      def backup_databases
        client = Mongo::Client.new(
          [server_uri], connect_timeout: 5, server_selection_timeout: 5, connect: :direct
        )
        client.database_names - %w(admin config local)
      ensure
        client&.close
      end

      def run_command command
        Rails.logger.debug command
        Rails.logger.debug `#{command}`
        $?.success?
      end
    end
  end
end
