module CloudModel
  module Workers
    module Services
      class RedisWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          comment_sub_step "Write redis config"
          @host.sftp.file.open(File.expand_path("etc/redis/redis.conf", @guest.deploy_path), 'w') do |f|
            f.write render("/cloud_model/guest/etc/redis/redis.conf", guest: @guest, model: @model)
          end
          if @model.redis_sentinel_set_id
            @host.sftp.file.open(File.expand_path("etc/redis/sentinel.conf", @guest.deploy_path), 'w') do |f|
              f.write render("/cloud_model/guest/etc/redis/sentinel.conf", guest: @guest, model: @model)
            end
          end

        end

        def service_name
          "redis-server"
        end

        def auto_restart
          true
        end

        def auto_start
          comment_sub_step "Add Redis Services to runlevel default"

          @host.exec "ln -sf /lib/systemd/system/redis_server.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"

          overlay_path = "#{@guest.deploy_path.shellescape}/etc/systemd/system/redis_server.service.d"
          mkdir_p overlay_path
          render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{overlay_path}/restart.conf"
          @host.exec  "chown -R 100000:100000 #{overlay_path}"


          if @model.redis_sentinel_set_id
            @host.exec "ln -sf /lib/systemd/system/redis_sentinel.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"

            overlay_path = "#{@guest.deploy_path.shellescape}/etc/systemd/system/redis_sentinel.service.d"
            mkdir_p overlay_path
            render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{overlay_path}/restart.conf"
            @host.exec  "chown -R 100000:100000 #{overlay_path}"
          end
        end
      end
    end
  end
end
