module CloudModel
  module Services
    class RedisWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Write redis config"
        @host.sftp.file.open(File.expand_path("etc/redis.conf", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/redis.conf", guest: @guest, model: @model)
        end
        
        log_dir_path = "/var/log/redis/"
        mkdir_p "#{@guest.deploy_path}#{log_dir_path}"
        @host.exec "chmod -R 2770 #{@guest.deploy_path}#{log_dir_path}"
        chroot @guest.deploy_path, "chown -R redis:redis #{log_dir_path}"
      end
    end
  end
end