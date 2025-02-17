module CloudModel
  module Monitoring
    class RedisSentinelSetChecks < CloudModel::Monitoring::BaseChecks
      def self.check options = {}
        CloudModel::RedisSentinelSet.scoped.each do |sentinel_set|
          handle_cloudmodel_monitoring_exception sentinel_set, '_Redis Sentinel_', 2 do
            if sentinel_set.active?
              CloudModel::Monitoring::RedisSentinelSetChecks.new(sentinel_set).check
            end
          end
        end
      end

      def acquire_data
        @subject.status
      end

      def line_prefix
        "[_Redis Sentinel_] #{super}"
      end

      def check
        do_check :set_health, 'Set Health', {critical: data[:key]==:not_reachable}, message: "Set not healthy"
        data
      end
    end
  end
end