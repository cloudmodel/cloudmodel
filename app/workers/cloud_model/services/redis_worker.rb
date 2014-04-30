module CloudModel
  module Services
    class RedisWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Write nginx config"
        @host.ssh_connection.sftp.file.open(File.expand_path("etc/redis.conf", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/redis.conf", guest: @guest, model: @model)
        end
        
        log_dir_path = "#{@guest.deploy_path}/var/log/redis/"
        mkdir_p log_dir_path
        @host.exec "chmod -R 2770 #{log_dir_path}"
        @host.exec "chown -R redis:redis #{log_dir_path}"
      end
    end
  end
end