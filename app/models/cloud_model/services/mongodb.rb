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
            
      def mongodb_replication_set_master?
        # guest.livestatus.services.find{|s| s.description == 'Mongodb-replicaset'}.perf_data['state'] == '1'
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
        # Not available via new livestatus based in check_mongodb.py
        # livestatus and livestatus.perf_data and livestatus.perf_data['repl_set_version']
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