module CloudModel
  module Monitoring
    class MongodbReplicationSetChecks < CloudModel::Monitoring::BaseChecks
      def self.check options = {}
        CloudModel::MongodbReplicationSet.scoped.each do |replication_set|
          handle_cloudmodel_monitoring_exception replication_set, '_Mongo Repl_', 2 do
            if replication_set.initiated? and replication_set.active?
              CloudModel::Monitoring::MongodbReplicationSetChecks.new(replication_set).check
            end
          end
        end
      end

      def line_prefix
        "[_Mongo Repl_] #{super}"
      end

      def acquire_data
        @subject.status service_id_only: true
      end

      def check
        if data[:members] and data[:members].size > 0
          do_check :set_health, 'Set Health', {critical: not(data['ok'] == 1.0)}, message: "Set not healthy"

          member_health = data[:members].select{|m| m["stateStr"] != "ARBITER"}.map{|m| m['health']}
          average = member_health.sum / member_health.size.to_f

          majority_healthy = average > 0.5
          healthy_services = data[:members].select{|m| m["health"] == 1.0}
          all_healthy = healthy_services.size == data[:members].size

          message = if not majority_healthy
            "Majority of operational members not healthy"
          else
            "Some Members or Arbiters are not healty"
          end

          do_check :member_health, 'Members Health', {critical: not(majority_healthy), warning: not(all_healthy)}, message: message

          check_replication_lag
          check_backup_freshness

          return (data['ok'] == 1.0 and all_healthy)
        end
      end

      # Secondary replication lag: how far behind the primary the furthest
      # secondary is (primary optime − secondary optime). Member up/down alone
      # doesn't catch a secondary that is healthy but falling behind — which
      # silently erodes read consistency and failover safety.
      def check_replication_lag
        members = data[:members].select { |m| m['optimeDate'] }
        primary = members.find { |m| m['stateStr'] == 'PRIMARY' }
        secondaries = members.select { |m| m['stateStr'] == 'SECONDARY' }
        return if primary.nil? or secondaries.empty?

        max_lag = secondaries.map { |m| (primary['optimeDate'] - m['optimeDate']).to_f }.max
        max_lag = 0.0 if max_lag < 0 # clock skew between members

        do_check_value :replication_lag, max_lag, {
          critical: 60,
          warning: 10
          }, unit: 's', name: 'Replication lag'
      end
    end
  end
end