require 'stringio'
require 'securerandom'

module CloudModel
  module Services
    class SolrWorker < CloudModel::Services::BaseWorker
      def write_config
        install_path = "#{@guest.deploy_path}/opt"
        config_path = "#{@guest.deploy_path}/var/solr"

        puts "        Deploy SOLR Mirror #{@model.deploy_solr_image.solr_version} to #{@guest.deploy_path}#{install_path}"
        temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar.bz2"
        io = StringIO.new(@model.deploy_solr_image.solr_mirror.file.data)
        @host.sftp.upload!(io, temp_file_name)
        mkdir_p install_path
        @host.exec "cd #{install_path.shellescape} && tar xzpf #{temp_file_name} && ln -s solr-#{@model.deploy_solr_image.solr_version.shellescape} solr"
        @host.sftp.remove!(temp_file_name)
        
        puts "        Deploy SOLR Config #{@model.deploy_solr_image.name} to #{@guest.deploy_path}#{config_path}"
        temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar.bz2"
        io = StringIO.new(@model.deploy_solr_image.file.data)
        @host.sftp.upload!(io, temp_file_name)
        mkdir_p "#{config_path}/solr"
        @host.exec "cd #{config_path.shellescape}/solr && tar xjpf #{temp_file_name}"
        @host.sftp.remove!(temp_file_name)

        chroot @guest.deploy_path, "chown -R solr:solr /var/solr"
        
        render_to_remote "/cloud_model/guest/etc/systemd/system/solr.service", "#{@guest.deploy_path}/etc/systemd/system/solr.service", guest: @guest, model: @model 
      end
    
      def service_name
        "solr"
      end
    end
  end
end