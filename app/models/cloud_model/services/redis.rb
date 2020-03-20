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
      
      def livestatus
        if guest.livestatus
          guest.livestatus.services.find{|s| s.description == 'Redis'}
        end
      end
      
      def redis_sentinel_master?
        redis_sentinel_set.try(:master_service) == self       
      end
      
      def redis_sentinel_slave?
        if redis_sentinel_set
          redis_sentinel_set.master_service != self
        else
          # If not member of a set, it can't be a slave
          false
        end       
      end
      
      def redis_sentinel_set_version
        'N/A'
      end
      
    end
  end
end