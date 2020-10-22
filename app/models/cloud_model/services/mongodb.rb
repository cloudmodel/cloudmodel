module CloudModel
  module Services
    class Mongodb < Base
      field :port, type: Integer, default: 27017
      belongs_to :mongodb_replication_set, class_name: "CloudModel::MongodbReplicationSet", optional: true

      def kind
        :mongodb
      end

      def components_needed
        [:mongodb]
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
          mongo_client = Mongo::Client.new(["#{server_uri}"], connect_timeout: 1, server_selection_timeout: 1)
          data = mongo_client.database.command('serverStatus' => true).first
        rescue Mongo::Error::NoServerAvailable => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        rescue Exception => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :warning}
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

      def backup
        return false unless has_backups
        timestamp = Time.now.strftime "%Y%m%d%H%M%S"
        FileUtils.mkdir_p backup_directory
        command = "LC_ALL=C mongodump -h #{guest.private_address} --port #{port} -o #{backup_directory}/#{timestamp}"

        Rails.logger.debug command
        Rails.logger.debug `#{command}`

        if $?.success? and File.exists? "#{backup_directory}/#{timestamp}"
          FileUtils.rm_f "#{backup_directory}/latest"
          FileUtils.ln_s "#{backup_directory}/#{timestamp}", "#{backup_directory}/latest"
          cleanup_backups

          return true
        else
          FileUtils.rm_rf "#{backup_directory}/#{timestamp}"
          return false
        end
      end

      def restore timestamp='latest'
        if File.exists? "#{backup_directory}/#{timestamp}"
          command = "LC_ALL=C mongorestore --drop -h #{guest.private_address} --port #{port} #{backup_directory}/#{timestamp}"

          Rails.logger.debug command
          Rails.logger.debug `#{command}`

          return $?.success?
        else
          return false
        end
      end
    end
  end
end