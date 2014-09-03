require 'stringio'
require 'securerandom'

module CloudModel
  module Services
    class NginxWorker < CloudModel::Services::BaseWorker
      def write_config
        puts "        Write nginx config"
                
        render_to_remote "/cloud_model/guest/etc/nginx/nginx.conf", "#{@guest.deploy_path}/etc/nginx/nginx.conf", guest: @guest, model: @model      
        render_to_remote "/cloud_model/guest/etc/conf.d/rails", "#{@guest.deploy_path}/etc/conf.d/rails", guest: @guest, model: @model
      
        puts "        Make nginx root"
        mkdir_p "#{@guest.deploy_path}#{@model.www_root}"
      
        if @model.ssl_supported?
          puts "    Copy SSL files"
          ssl_base_dir = File.expand_path("etc/nginx/ssl", @guest.deploy_path)
          mkdir_p ssl_base_dir
                  
          @host.ssh_connection.sftp.file.open(File.expand_path("#{@guest.external_hostname}.crt", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.crt
          end
        
          @host.ssh_connection.sftp.file.open(File.expand_path("#{@guest.external_hostname}.key", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.key
          end
        
          @host.ssh_connection.sftp.file.open(File.expand_path("#{@guest.external_hostname}.ca.crt", ssl_base_dir), 'w') do |f|
            f.write @model.ssl_cert.ca
          end
        end
       
        if @model.deploy_web_image
          mkdir_p "#{@guest.deploy_path}#{@model.www_root}/current"
        
          puts "        Deploy WebImage #{@model.deploy_web_image.name} to #{@guest.deploy_path}#{@model.www_root}"
          temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar"
          io = StringIO.new(@model.deploy_web_image.file.data)
          @host.ssh_connection.sftp.upload!(io, temp_file_name)
          @host.exec "cd #{@guest.deploy_path}#{@model.www_root} && tar xpf #{temp_file_name}"
          @host.ssh_connection.sftp.remove!(temp_file_name)
          
          if @model.deploy_web_image.has_mongodb?
            render_to_remote "/cloud_model/web_image/mongoid.yml", "#{@guest.deploy_path}#{@model.www_root}/current/config/mongoid.yml", guest: @guest, model: @model
          end
        
          if @model.deploy_web_image.has_redis?
            render_to_remote "/cloud_model/web_image/redis.yml", "#{@guest.deploy_path}#{@model.www_root}/current/config/redis.yml", guest: @guest, model: @model
          end
        end
      
        @host.exec "chmod -R 2775 #{@guest.deploy_path}#{@model.www_root}"
        @host.exec "chown -R www:www #{@guest.deploy_path}#{@model.www_root}"
        
        log_dir_path = "#{@guest.deploy_path}/var/log/nginx/"
        mkdir_p log_dir_path
        @host.exec "chmod -R 2770 #{log_dir_path}"
        @host.exec "chown -R www:www #{log_dir_path}"
      end
    
      def auto_start
        super
        # TODO: Resolve dependencies
        # Services::Ssh.new(@host, @options).write_config
      end
    end
  end
end