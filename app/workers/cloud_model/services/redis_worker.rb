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
      
      def auto_start
        puts "        Add Redis to runlevel default"
        @host.exec "ln -sf /lib/systemd/system/redis-server.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
      end
      
    end
  end
end

