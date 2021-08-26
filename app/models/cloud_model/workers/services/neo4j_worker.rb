module CloudModel
  module Workers
    module Services
      class Neo4jWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          target = '/var/lib/neo4j'

          comment_sub_step "Write neo4j config"
          @host.sftp.file.open("#{@guest.deploy_path.shellescape}/etc/neo4j/neo4j.conf", 'w') do |f|
            f.write render("/cloud_model/guest/etc/neo4j/neo4j.conf", guest: @guest, model: @model)
          end
        end

        def auto_restart
          true
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/neo4j.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
          super
        end
      end
    end
  end
end