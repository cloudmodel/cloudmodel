require 'redis'

module CloudModel
  # Manages a Redis Sentinel high-availability set.
  #
  # Multiple {Services::Redis} instances reference a RedisSentinelSet via
  # `redis_sentinel_set_id`. The {#master_service} is the primary Redis node;
  # sentinels monitor it and promote a replica automatically on failure.
  # {#status} connects to the sentinel port and returns live Redis INFO data.
  class RedisSentinelSet
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] name
    #   @return [String] sentinel set name (used in sentinel.conf as `sentinel monitor <name>`)
    field :name, type: String

    # @!attribute [rw] active
    #   @return [Boolean, nil] whether the sentinel set is considered active
    field :active, type: Boolean

    # @!attribute [rw] master_service
    #   @return [CloudModel::Services::Redis, nil] the designated primary Redis service
    belongs_to :master_service, class_name: "CloudModel::Services::Redis", optional: true

    # @return [Array<CloudModel::Services::Redis>] all Redis services in this sentinel set
    def services
      CloudModel::Guest.where("services.redis_sentinel_set_id" => id).map{ |guest|
        guest.services.where(redis_sentinel_set_id: id).to_a
      }.flatten
    end

    # Adds a Redis service to this sentinel set.
    # @param service [CloudModel::Services::Redis]
    def add_service service
      service.update_attribute :redis_sentinel_set_id, id
    end

    def master_service
      if master_service_id
        CloudModel::Services::Base.find(master_service_id)
      else
        services.first
      end
    end

    # @return [CloudModel::Guest] the guest running the master Redis service
    def master_node
      master_service.guest
    end

    # @return [String] private IP address of the master node
    def master_address
      master_node.private_address
    end

    # Returns `{ 'ip' => ..., 'port' => ... }` for each sentinel service.
    # @return [Array<Hash>]
    def sentinel_hosts
      services.map do |s|
        {'ip' => s.private_address, 'port' => s.redis_sentinel_port}
      end
    end

    # Connects to the master sentinel port and returns Redis INFO data.
    # @return [Hash] Redis INFO hash, or an error hash with `:key`, `:error`, `:severity`
    def status options={}
      begin
        redis = ::Redis.new(host: master_service.private_address, port: master_service.redis_sentinel_port, db: 0)

        data = redis.info
      rescue ::Redis::CannotConnectError => e
        return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
      rescue Exception => e
        return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :warning}
      ensure
        redis.close if redis
      end

      # Remove keys containing config details and doubled values
      %w(redis_version redis_git_sha1 redis_mode config_file mem_allocator redis_build_id os arch_bits multiplexing_api gcc_version process_id run_id used_memory_human used_memory_peak_human ).each do |k|
        data.delete(k)
      end

      data
    end
  end
end