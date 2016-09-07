module CloudModel
  module Services
    class Redis < Base
      field :port, type: Integer, default: 6379
      field :redis_sentinel_port, type: Integer, default: 26379
      
      belongs_to :redis_sentinel_set, class_name: "CloudModel::RedisSentinelSet"
      
      def kind
        :redis
      end
      
      def components_needed
        [:redis]
      end
      
      def shinken_services_append
        ', redis'
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