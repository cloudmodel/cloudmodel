module CloudModel
  module Services
    class RedisWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Install Redis"
        chroot! @guest.deploy_path, "apt-get install redis-server -y", "Failed to install Redis"
        
        puts "        Write redis config"
        @host.sftp.file.open(File.expand_path("etc/redis/redis.conf", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/redis/redis.conf", guest: @guest, model: @model)
        end
      end
      
      def service_name
        "redis-server"
      end
      
      def auto_restart
        true
      end 
    end
  end
end

