require 'redis'

module CloudModel
  module Services
    class RedisChecks < CloudModel::Services::BaseChecks      
      def get_result        
        begin
          redis = ::Redis.new(host: @guest.private_address, port: @subject.port, db: 0)

          data = redis.info
        rescue ::Redis::CannotConnectError => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        rescue Exception => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :warning}
        end

        # Remove keys containing config details and doubled values
        %w(redis_version redis_git_sha1 redis_mode config_file mem_allocator redis_build_id os arch_bits multiplexing_api gcc_version process_id run_id used_memory_human used_memory_peak_human ).each do |k|
          data.delete(k)
        end
        
        data
      end
      
      def check
        do_check_for_errors_on @result, {
          not_reachable: 'service reachable'
        }
      end
    end
  end
end

