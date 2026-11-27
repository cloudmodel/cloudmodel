module CloudModel
  module Workers
    module Services
      # Worker that configures the MySQL server (see {Services::Mysql}) inside a guest
      # container: server options (localhost only, root over the socket,
      # telemetry on or off), the telemetry agent and a `mysql.service`
      # drop-in that initialises an empty data directory (a fresh data
      # volume) before the first start and switches root to `auth_socket`
      # after every start.
      class MysqlWorker < CloudModel::Workers::Services::BaseWorker
        include PerconaTelemetry

        def service_name
          "mysql"
        end

        def write_config
          comment_sub_step "Write MySQL #{@model.effective_mysql_version} (#{@model.mysql_distribution}) config (telemetry #{@model.telemetry ? 'on' : 'off'})"
          render_to_guest "/cloud_model/guest/etc/mysql/mysql.conf.d/zz-cloudmodel.cnf", "/etc/mysql/mysql.conf.d/zz-cloudmodel.cnf", 0644, guest: @guest, model: @model
          write_percona_telemetry_agent @model.telemetry if @model.percona?
        end

        def auto_restart
          true
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/mysql.service.d/cloudmodel.conf", "#{overlay_path}/cloudmodel.conf", 0644, model: @model
          super
        end
      end
    end
  end
end
