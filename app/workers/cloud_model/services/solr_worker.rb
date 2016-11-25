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
        mkdir_p config_path
        @host.exec "cd #{config_path.shellescape}/solr && tar xjpf #{temp_file_name}"
        @host.sftp.remove!(temp_file_name)

        @host.exec "chown -R solr:solr #{config_path.shellescape}"
        
        render_to_remote "/cloud_model/guest/etc/systemd/system/solr.service", "#{@guest.deploy_path}/etc/systemd/system/solr.service", guest: @guest, model: @model 
        

        # # Read manifest
        # manifest = ''
        # @host.sftp.file.open( "#{target}/manifest.yml") do |f|
        #   manifest = YAML.load(f.read)
        # end
        #
        # puts "        Write tomcat config"
        # tomcat_conf_dir = '/etc/tomcat8'
        # #tomcat_conf_dir = '/usr/share/tomcat8/conf'
        #
        # mkdir_p "#{@guest.deploy_path}#{tomcat_conf_dir}/Catalina/localhost"
        #
        # render_to_remote "/cloud_model/guest/etc/default/tomcat8", "#{@guest.deploy_path}/etc/default/tomcat8", manifest: manifest, worker: self, guest: @guest, model: @model
        # render_to_remote "/cloud_model/guest/etc/tmpfiles.d/tomcat8.conf", "#{@guest.deploy_path}/etc/tmpfiles.d/tomcat8.conf"
        # render_to_remote "/cloud_model/guest/etc/tomcat8/server.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/server.xml", 0640, guest: @guest, model: @model
        # render_to_remote "/cloud_model/guest/etc/tomcat8/servlet.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/Catalina/localhost/ROOT.xml", 0640, manifest: manifest, worker: self, guest: @guest, model: @model
        # render_to_remote "/cloud_model/guest/etc/tomcat8/tomcat-users.xml", "#{@guest.deploy_path}#{tomcat_conf_dir}/tomcat-users.xml", 0640, guest: @guest, model: @model
        # chroot! @guest.deploy_path, "rm -rf /var/lib/tomcat8/webapps/ROOT", "Failed to remove genuine root app for tomcat"
        #
        #
        # chroot @guest.deploy_path, "chown -R tomcat8:tomcat8 /var/tomcat #{tomcat_conf_dir}"
      end
    
      def service_name
        "solr"
      end
    end
  end
end