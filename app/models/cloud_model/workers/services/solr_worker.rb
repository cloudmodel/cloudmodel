require 'stringio'
require 'securerandom'

module CloudModel
  module Workers
    module Services
      class SolrWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          install_path = "/tmp/opt"
          config_path = "/tmp/solr"

          comment_sub_step "Deploy SOLR Mirror #{@model.deploy_solr_image.solr_version}"
          temp_file_name = "#{install_path.shellescape}.tar.bz2"
          io = StringIO.new(@model.deploy_solr_image.solr_mirror.file.data)
          @host.sftp.upload!(io, temp_file_name)
          mkdir_p install_path
          @host.exec "cd #{install_path.shellescape} && tar xzpf #{temp_file_name}"
          @host.sftp.remove!(temp_file_name)

          solr_version = @model.deploy_solr_image.solr_version.shellescape
          @host.exec! "rm #{install_path}/solr; ln -s /opt/solr-#{solr_version} #{install_path.shellescape}/solr", "Failed to create link to solr version"
          # Patch log4j config to set path to log
          @host.exec "sed -i 's/solr\.log=logs/solr.log=\/var\/solr\/log/' #{install_path.shellescape}/solr-#{solr_version}/server/resources/log4j.properties"

          @host.exec!("lxc file push #{install_path.shellescape}/ #{@lxc.name}/ -p -r && rm -rf #{install_path.shellescape}", "Failed to upload SOLR Mirror to container")

          comment_sub_step "Deploy SOLR Config #{@model.deploy_solr_image.name}"
          temp_file_name = "#{config_path.shellescape}.tar.bz2"
          io = StringIO.new(@model.deploy_solr_image.file.data)
          @host.sftp.upload!(io, temp_file_name)
          mkdir_p "#{config_path.shellescape}/solr"
          @host.exec "cd #{config_path.shellescape}/solr && tar xjpf #{temp_file_name}"
          @host.sftp.remove!(temp_file_name)

          # Create log folder
          mkdir_p "#{config_path.shellescape}/log"
          mkdir_p "#{config_path.shellescape}/cache"
          mkdir_p "#{config_path.shellescape}/data"

          @host.exec! "chown -R 100999:100999  #{config_path.shellescape}", "Failed to setup rights"

          @host.exec!("lxc file push #{config_path.shellescape}/ #{@lxc.name}/var/ -p -r && rm -rf #{config_path.shellescape}", "Failed to upload SOLR Config to container")

          render_to_guest "/cloud_model/guest/etc/systemd/system/solr.service", "/etc/systemd/system/solr.service", 0755, guest: @guest, model: @model
        end

        def service_name
          "solr"
        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/solr.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf"
          super
        end
      end
    end
  end
end