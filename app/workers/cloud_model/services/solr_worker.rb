require 'stringio'
require 'securerandom'

module CloudModel
  module Services
    class SolrWorker < CloudModel::Services::BaseWorker
      def write_config
        install_path = "#{@guest.deploy_path}/opt"
        config_path = "#{@guest.deploy_path}/var/solr"

        puts "        Deploy SOLR Mirror #{@model.deploy_solr_image.solr_version} to #{install_path}"
        temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar.bz2"
        io = StringIO.new(@model.deploy_solr_image.solr_mirror.file.data)
        @host.sftp.upload!(io, temp_file_name)
        mkdir_p install_path
        @host.exec "cd #{install_path.shellescape} && tar xzpf #{temp_file_name}"
        @host.sftp.remove!(temp_file_name)
        
        solr_version = @model.deploy_solr_image.solr_version.shellescape
        chroot @guest.deploy_path, "ln -s /opt/solr-#{solr_version} /opt/solr"
        # Patch log4j config to set path to log
        @host.exec "sed -i 's/solr\.log=logs/solr.log=\/var\/solr\/log/' #{install_path.shellescape}/solr-#{solr_version}/server/resources/log4j.properties"
        
        puts "        Deploy SOLR Config #{@model.deploy_solr_image.name} to #{config_path}"
        temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar.bz2"
        io = StringIO.new(@model.deploy_solr_image.file.data)
        @host.sftp.upload!(io, temp_file_name)
        mkdir_p "#{config_path}/solr"
        @host.exec "cd #{config_path.shellescape}/solr && tar xjpf #{temp_file_name}"
        @host.sftp.remove!(temp_file_name)

        # Create log folder
        mkdir_p "#{config_path}/log"

        chroot @guest.deploy_path, "chown -R solr:solr /var/solr"
        
        render_to_remote "/cloud_model/guest/etc/systemd/system/solr.service", "#{@guest.deploy_path}/etc/systemd/system/solr.service", guest: @guest, model: @model 
      end
    
      def service_name
        "solr"
      end
    end
  end
end