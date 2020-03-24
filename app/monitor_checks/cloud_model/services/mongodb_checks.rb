module CloudModel
  module Services
    class MongodbChecks < CloudModel::Services::BaseChecks
      def sanitize_data data
        data.keys.each do |k|
          if k =~ /^\$/
            new_k = k.gsub(/^\$/, '')
            data[new_k] = data.delete k
            k = new_k
          end
          
          v = data[k]
          if v.is_a? Hash
            data[k] = sanitize_data data[k]
          end
        end
        data
      end
      
      def get_result
        begin  
          mongo_client = Mongo::Client.new(["#{@guest.private_address}:#{@subject.port}"], connect_timeout: 1, server_selection_timeout: 1)
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
        
        sanitize_data data.as_json
      end
    
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable'
        }
      end
    end
  end
end