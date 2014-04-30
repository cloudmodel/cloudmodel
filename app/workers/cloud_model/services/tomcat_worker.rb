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
        @host.ssh_connection.sftp.upload!(io, temp_file_name)     
        mkdir_p target
        @host.exec "cd #{target.shellescape} && tar xjpf #{temp_file_name}"
        @host.ssh_connection.sftp.remove!(temp_file_name)
            
        # Read manifest
        manifest = ''
        @host.ssh_connection.sftp.file.open( "#{target}/manifest.yml") do |f|
          manifest = YAML.load(f.read)
        end
        
        puts "        Write tomcat config"
        @host.ssh_connection.sftp.file.open(File.expand_path("etc/tomcat-7/server.xml", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/tomcat-7/server.xml", guest: @guest, model: @model)
        end
              
        @host.ssh_connection.sftp.file.open(File.expand_path("etc/conf.d/tomcat-7", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/conf.d/tomcat-7", manifest: manifest, worker: self, guest: @guest, model: @model)
        end
              
        @host.ssh_connection.sftp.file.open(File.expand_path("etc/tomcat-7/Catalina/localhost/ROOT.xml", @guest.deploy_path), 'w') do |f|
          f.write render("/cloud_model/guest/etc/tomcat-7/servlet.xml", manifest: manifest, worker: self, guest: @guest, model: @model)
        end
              
        @host.exec "chown -R 265:265 #{target.shellescape}"
      end
    
      def interpolate_value(value)
        value.to_s.gsub("%TARGET%", "/var/tomcat").gsub("%DATA_DIR%", "/var/tomcat/data")
      end
    
      def auto_start
        puts "        Add Tomcat to runlevel default"
        @host.exec "ln -sf /etc/init.d/tomcat-7 #{@guest.deploy_path.shellescape}/etc/runlevels/default/"
      end
    end
  end
end