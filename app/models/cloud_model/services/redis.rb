module CloudModel
  module Services
    class Redis < Base
      field :port, type: Integer, default: 6379
      field :redis_sentinel_port, type: Integer, default: 26379
      field :redis_sentinel_set_id, type: BSON::ObjectId

      def redis_sentinel_set
        CloudModel::RedisSentinelSet.where(id: redis_sentinel_set_id).first if :redis_sentinel_set_id
      end
      
      def redis_sentinel_set=(set)
        self.redis_sentinel_set_id = set.try(:id)
      end
      
      def kind
        :redis
      end
      
      def components_needed
        [:redis]
      end
            
      def redis_sentinel_master?
        if monitoring_last_check_result
          monitoring_last_check_result['role'] == 'master'
        else
          if redis_sentinel_set
            redis_sentinel_set.try(:master_service) == self 
          else
            false
          end
        end
      end
      
      def redis_sentinel_slave?
        not redis_sentinel_master?
      end
      
      def redis_sentinel_set_version 
        'N/A'
      end
      
    end
  end
end