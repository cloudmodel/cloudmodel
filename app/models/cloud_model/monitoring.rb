require_relative "monitoring/base_checks"
require_relative "monitoring/mixins/sysinfo_checks_mixin"
require_relative "monitoring/host_checks"
require_relative "monitoring/guest_checks"
require_relative "monitoring/service_checks"
require_relative "monitoring/lxd_custom_volume_checks"
require_relative "monitoring/mongodb_replication_set_checks"
require_relative "monitoring/redis_sentinel_set_checks"

module CloudModel
  module Monitoring
    def self.check
      @checks ||= []
      @checks.each do |check|
        check.check
      end
    end

    def self.register_check check
      @checks ||= []
      @checks << check
    end
  end
end

CloudModel::Monitoring.register_check CloudModel::Monitoring::HostChecks
#CloudModel::Monitoring.register_check CloudModel::Monitoring::MongodbReplicationSetChecks
#CloudModel::Monitoring.register_check CloudModel::Monitoring::RedisSentinelSetChecks
