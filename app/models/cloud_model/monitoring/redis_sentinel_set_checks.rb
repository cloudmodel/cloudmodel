module CloudModel
  module Monitoring
    class RedisSentinelSetChecks < CloudModel::Monitoring::BaseChecks
      def initialize redis_sentinel_set, options = {}
        puts "[RedisSentinelSet #{redis_sentinel_set.name}]"
        @indent = 0
        @subject = redis_sentinel_set
      end
    
      def check
        
      end
    end
  end
end