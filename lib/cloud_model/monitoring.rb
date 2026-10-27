module CloudModel
  module Monitoring
    module Services
    end

    def self.check
      started = Time.now
      CloudModel::MonitoringHeartbeat.start! started_at: started
      @checks ||= []
      @checks.each do |check|
        # Isolate each registered check group. A failure in one group (an
        # unreachable driver, a DB hiccup, a bug) must not abort the whole run
        # or the caller's subsequent RRD rollup — it opens a keyed,
        # subject-less ItemIssue (check_crashed_<group>) and we move on. The
        # issue auto-resolves the next time the group completes cleanly.
        key = check.name.to_s.demodulize.underscore.to_sym
        CloudModel::Monitoring::BaseChecks.handle_cloudmodel_monitoring_exception key, '_Monitoring_', 0 do
          check.check
        end
      end
    ensure
      # Issues that survived this cycle unreported get reported now, and the
      # watchdog learns that this admin completed a cycle.
      CloudModel::Monitoring::BaseChecks.handle_cloudmodel_monitoring_exception :notify_due, '_Monitoring_', 0 do
        sent = CloudModel::ItemIssue.notify_due!
        puts "[_Monitoring_] #{sent} confirmed issue(s) reported" if sent > 0
      end
      CloudModel::MonitoringHeartbeat.beat! started_at: started
    end

    def self.register_check check
      @checks ||= []
      @checks << check
    end
  end
end

require_relative "monitoring/base_checks"
require_relative "monitoring/mixins/sysinfo_checks_mixin"
require_relative "monitoring/host_checks"
require_relative "monitoring/guest_checks"
require_relative "monitoring/service_checks"
require_relative "monitoring/certificate_checks"
require_relative "monitoring/lxd_custom_volume_checks"
require_relative "monitoring/mongodb_replication_set_checks"
require_relative "monitoring/redis_sentinel_set_checks"
require_relative "monitoring/heartbeat_checks"

CloudModel::Monitoring.register_check CloudModel::Monitoring::HostChecks
CloudModel::Monitoring.register_check CloudModel::Monitoring::MongodbReplicationSetChecks
CloudModel::Monitoring.register_check CloudModel::Monitoring::RedisSentinelSetChecks
CloudModel::Monitoring.register_check CloudModel::Monitoring::CertificateChecks
CloudModel::Monitoring.register_check CloudModel::Monitoring::HeartbeatChecks
