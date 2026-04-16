module CloudModel
  module Services
    # Redis key-value store service embedded in a {Guest}.
    #
    # Supports standalone and Sentinel high-availability configurations.
    # When assigned to a {RedisSentinelSet}, `redis_sentinel_port` is used
    # by the Sentinel process on the same container. {#redis_sentinel_master?}
    # reflects whether this node is currently the primary.
    class Redis < Base
      # @!attribute [rw] port
      #   @return [Integer] Redis data port (default: 6379)
      field :port, type: Integer, default: 6379

      # @!attribute [rw] redis_sentinel_port
      #   @return [Integer] Redis Sentinel port (default: 26379)
      field :redis_sentinel_port, type: Integer, default: 26379

      # @!attribute [rw] redis_sentinel_set
      #   @return [CloudModel::RedisSentinelSet, nil] the sentinel set this node belongs to
      belongs_to :redis_sentinel_set, class_name: "CloudModel::RedisSentinelSet", optional: true

      def kind
        :redis
      end

      def components_needed
        ([:redis] + super).uniq
      end

      def service_status
        begin
          redis = ::Redis.new(host: guest.private_address, port: port, db: 0)

          data = redis.info
        rescue ::Redis::CannotConnectError => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        rescue Exception => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :warning}
        ensure
          redis.close
        end

        # Remove keys containing config details and doubled values
        %w(redis_version redis_git_sha1 redis_mode config_file mem_allocator redis_build_id os arch_bits multiplexing_api gcc_version process_id run_id used_memory_human used_memory_peak_human ).each do |k|
          data.delete(k)
        end

        data
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