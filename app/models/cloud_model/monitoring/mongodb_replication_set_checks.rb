module CloudModel
  module Monitoring
    class MongodbReplicationSetChecks < CloudModel::Monitoring::BaseChecks
      def initialize mongodb_replication_set, options = {}
        puts "[MongodbReplicationSet #{mongodb_replication_set.name}]"
        @indent = 0
        @subject = mongodb_replication_set
      end
    
      def check
        
      end
    end
  end
end