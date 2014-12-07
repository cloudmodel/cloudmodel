require 'stringio'
require 'securerandom'

module CloudModel
  module Services
    class TomcatWorker < CloudModel::Services::BaseWorker
      def write_config
        target = "#{@guest.deploy_path}/var/tomcat" 
         
        puts "        Deploy WAR Image #{@model.deploy_war_image.name} to #{@guest.deploy_path}#{target}"
        temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar"
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
        
        puts "        Write tomcat config"
        mkdir_p File.expand_path("etc/tomcat-7/Catalina/localhost", @guest.deploy_path) 
        
        render_to_remote "/cloud_model/guest/etc/conf.d/tomcat-7", "#{@guest.deploy_path}/etc/conf.d/tomcat-7", manifest: manifest, worker: self, guest: @guest, model: @model     
        render_to_remote "/cloud_model/guest/etc/tomcat-7/server.xml", "#{@guest.deploy_path}/etc/tomcat-7/server.xml", 0640, guest: @guest, model: @model      
        render_to_remote "/cloud_model/guest/etc/tomcat-7/servlet.xml", "#{@guest.deploy_path}/etc/tomcat-7/Catalina/localhost/ROOT.xml", 0640, manifest: manifest, worker: self, guest: @guest, model: @model    
        render_to_remote "/cloud_model/guest/etc/tomcat-7/tomcat-users.xml", "#{@guest.deploy_path}/etc/tomcat-7/tomcat-users.xml", 0640, guest: @guest, model: @model      
        
        chroot @guest.deploy_path, "chown -R tomcat:tomcat /var/tomcat /etc/tomcat-7/server.xml /etc/tomcat-7/Catalina/localhost /etc/tomcat-7/tomcat-users.xml"
      end
    
      def interpolate_value(value)
        value.to_s.gsub("%TARGET%", "/var/tomcat").gsub("%DATA_DIR%", "/var/tomcat/data")
      end
    
      def auto_start
        puts "        Add Tomcat to runlevel default"
        @host.exec "ln -sf /etc/systemd/system/tomcat-7.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"
      end
    end
  end
end