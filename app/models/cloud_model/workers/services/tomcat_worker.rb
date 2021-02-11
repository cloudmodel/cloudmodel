require 'stringio'
require 'securerandom'

module CloudModel
  module Workers
    module Services
      class TomcatWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          target = "#{@guest.deploy_path}/var/tomcat"

          comment_sub_step "Deploy WAR Image #{@model.deploy_war_image.name} to #{@guest.deploy_path}#{target}"
          temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar.bz2"
          io = StringIO.new(@model.deploy_war_image.file.data)
          @host.sftp.upload!(io, temp_file_name)
          mkdir_p target
          @host.exec "cd #{target.shellescape} && tar xjpf #{temp_file_name}"
          @host.sftp.remove!(temp_file_name)

          # Read manifest
          manifest = ''
          @host.sftp.file.open( "#{target}/manifest.yml") do |f|
            manifest = YAML.load(f.read)
          end

          comment_sub_step "Write tomcat config"
          tomcat_conf_dir = '/etc/tomcat8'
          #tomcat_conf_dir = '/usr/share/tomcat8/conf'

          mkdir_p "#{@guest.deploy_path}#{tomcat_conf_dir}/Catalina/localhost"

          render_to_remote "/cloud_model/guest/etc/default/tomcat8", "#{@guest.deploy_path}/etc/default/tomcat8", manifest: manifest, worker: self, guest: @guest, model: @model
          render_to_remote "/cloud_model/guest/etc/tmpfiles.d/tomcat8.conf", "#{@guest.deploy_path}/etc/tmpfiles.d/tomcat8.conf"
          render_to_remote "/cloud_model/guest/etc/tomcat8/server.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/server.xml", 0640, guest: @guest, model: @model
          render_to_remote "/cloud_model/guest/etc/tomcat8/servlet.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/Catalina/localhost/ROOT.xml", 0640, manifest: manifest, worker: self, guest: @guest, model: @model
          render_to_remote "/cloud_model/guest/etc/tomcat8/tomcat-users.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/tomcat-users.xml", 0640, guest: @guest, model: @model
          chroot! @guest.deploy_path, "rm -rf /var/lib/tomcat8/webapps/ROOT", "Failed to remove genuine root app for tomcat"


          chroot @guest.deploy_path, "chown -R tomcat8:tomcat8 /var/tomcat #{tomcat_conf_dir}"
        end

        def interpolate_value(value)
          value.to_s.gsub("%TARGET%", "/var/tomcat").gsub("%DATA_DIR%", "/var/tomcat/data")
        end

        def service_name
          "tomcat8"
        end

        def auto_start
          comment_sub_step "Add Tomcat to runlevel default"
          @host.exec "ln -sf /etc/systemd/system/tomcat8.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"

          mkdir_p overlay_path
          render_to_remote "/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{overlay_path}/restart.conf"
          render_to_remote "/cloud_model/guest/etc/systemd/system/tomcat8.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
          @host.exec  "chown -R 100000:100000 #{overlay_path}"
        end
      end
    end
  end
end