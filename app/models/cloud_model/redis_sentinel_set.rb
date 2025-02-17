require 'redis'

module CloudModel
  class RedisSentinelSet
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    field :name, type: String
    field :active, type: Boolean

    belongs_to :master_service, class_name: "CloudModel::Services::Redis", optional: true

    def services
      CloudModel::Guest.where("services.redis_sentinel_set_id" => id).map{ |guest|
        guest.services.where(redis_sentinel_set_id: id).to_a
      }.flatten
    end

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

    def master_node
      master_service.guest
    end

    def master_address
      master_node.private_address
    end

    def sentinel_hosts
      services.map do |s|
        {'ip' => s.private_address, 'port' => s.redis_sentinel_port}
      end
    end

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