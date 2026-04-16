module CloudModel
  module Workers
    module Components
      # Component worker that installs Redis server and Redis Sentinel
      # into a guest template chroot.
      class RedisComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install redis-server redis-sentinel -y", "Failed to install Redis"
        end
      end
    end
  end
end