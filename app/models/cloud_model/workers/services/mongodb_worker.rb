module CloudModel
  module Workers
    module Services
      # Worker that configures the MongoDB service inside a guest container.
      #
      # Renders `mongod.conf` and writes a fix-permissions systemd drop-in so
      # the MongoDB data directory is owned correctly on startup.
      class MongodbWorker < CloudModel::Workers::Services::BaseWorker
        def service_name
          "mongod"
        end

        def write_config
          target = '/var/lib/mongodb'

          comment_sub_step "Write mongodb config"
          @host.sftp.file.open("#{@guest.deploy_path.shellescape}/etc/mongod.conf", 'w') do |f|
            f.write render("/cloud_model/guest/etc/mongodb_conf", guest: @guest, model: @model)
          end
        end

        def auto_restart
          true
        end

        # Brings the running mongod onto the current memory/cache settings
        # without a restart where it can: writes mongod.conf into the running
        # container (so the next start keeps it) and resizes the WiredTiger
        # cache in place. Only if mongod refuses and `restart: true` it is
        # restarted — a primary steps down first, so the set elects another
        # member instead of losing writes for the length of the restart.
        # @return [Symbol] :live or :restarted
        def apply_wiredtiger_cache_live! restart: false
          upload_to_guest render("/cloud_model/guest/etc/mongodb_conf", guest: @guest, model: @model), '/etc/mongod.conf', '0644'
          begin
            @model.set_runtime_wiredtiger_cache!
            :live
          rescue => e
            raise unless restart
            CloudModel.log_exception e
            if @model.mongodb_replication_set and @model.running_primary?
              @model.guest.exec "/usr/bin/mongosh --quiet --eval 'rs.stepDown(60)'"
            end
            @model.guest.exec! "/bin/systemctl restart mongod", "Failed to restart mongod"
            :restarted
          end
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/mongodb_service_d/fix_perms_conf", "#{overlay_path}/fix_perms.conf"
          super
        end
      end
    end
  end
end