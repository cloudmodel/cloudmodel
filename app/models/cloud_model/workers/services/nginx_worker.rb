require 'stringio'
require 'securerandom'

module CloudModel
  module Workers
    module Services
      class NginxWorker < CloudModel::Workers::Services::BaseWorker
      
        def unroll_web_image deploy_path
          return false unless @model.deploy_web_image
        
          mkdir_p deploy_path
      
          puts "        Deploy WebImage #{@model.deploy_web_image.name} to #{deploy_path}"
          temp_file_name = "/tmp/temp-#{SecureRandom.uuid}.tar"
          io = StringIO.new(@model.deploy_web_image.file.data)
          @host.sftp.upload!(io, temp_file_name)
          @host.exec "cd #{deploy_path} && tar xpf #{temp_file_name}"
          @host.sftp.remove!(temp_file_name)
        
          mkdir_p "#{deploy_path}/config"
        
          if @model.deploy_web_image.has_mongodb?
            render_to_remote "/cloud_model/web_image/mongoid.yml", "#{deploy_path}/config/mongoid.yml", guest: @guest, model: @model
          end
      
          if @model.deploy_web_image.has_redis?
            if @model.deploy_redis_sentinel_set
              render_to_remote "/cloud_model/web_image/sentinel.yml", "#{deploy_path}/config/redis.yml", guest: @guest, model: @model
            else
              render_to_remote "/cloud_model/web_image/redis.yml", "#{deploy_path}/config/redis.yml", guest: @guest, model: @model
            end
          end
        
          mkdir_p "#{deploy_path}/tmp"
          @host.exec "touch #{deploy_path}/tmp/restart.txt"
        end
      
        def make_deploy_web_image_id
          "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
        end
      
        def deploy_web_image 
          if @model.deploy_web_image
            deploy_id = make_deploy_web_image_id
            deploy_path = "#{@guest.deploy_path}#{@model.www_root}/#{deploy_id}"
          
            unroll_web_image deploy_path
                
            @host.exec! "cd #{@guest.deploy_path}#{@model.www_root}; rm current; ln -s #{deploy_id} current", "Failed to set current"
          end
        end
      
        def redeploy_web_image options={}
          return false unless options[:force] or (@model.deploy_web_image and @model.redeploy_web_image_state == :pending)
        
          @model.update_attributes redeploy_web_image_state: :running, redeploy_web_image_last_issue: nil    
        
          puts "  Deploy to #{@guest.name}: #{@model.name}"
          begin      
            deploy_id = make_deploy_web_image_id
            unroll_path = "/tmp/webimage_unroll_#{@model.id}"
            deploy_path = "#{unroll_path}/var/www/rails/#{deploy_id}"

            @host.exec! "rm -rf #{unroll_path}", "Failed to clean unroll path"
            mkdir_p deploy_path
            unroll_web_image deploy_path

            @host.exec! "cd #{unroll_path} && tar c . | virsh lxc-enter-namespace #{@model.guest.name.shellescape} --noseclabel -- /bin/tar x", "Failed to transfer files"
            @host.exec "rm -rf #{unroll_path}"
            @model.guest.exec! "/bin/chown -R 101001:101001 #{@model.www_root}/#{deploy_id}", "Failed to set user to www "
          
            @model.guest.exec! "/bin/rm -f #{@model.www_root}/current", "Failed to remove old current"
            @model.guest.exec! "/bin/ln -s #{@model.www_root}/#{deploy_id} #{@model.www_root}/current", "Failed to set current"
            @model.guest.exec! "/bin/touch #{@model.www_root}/current/tmp/restart.txt", "Failed to restart service"
          rescue Exception => e
            CloudModel.log_exception e
            @model.update_attributes redeploy_web_image_state: :failed, redeploy_web_image_last_issue: "#{e}" 
            return false     
          end
          @model.update_attributes redeploy_web_image_state: :finished
        end
      
        def write_config         
          puts "        Config nginx"
                
          render_to_remote "/cloud_model/guest/etc/nginx/nginx.conf", "#{@guest.deploy_path}/etc/nginx/nginx.conf", guest: @guest, model: @model      
          render_to_remote "/cloud_model/guest/etc/default/rails", "#{@guest.deploy_path}/etc/default/rails", guest: @guest, model: @model
          chroot! @guest.deploy_path, "groupadd -f -r -g 1001 www && useradd -c 'added by cloud_model for nginx' -d /var/www -s /bin/bash -r -g 1001 -u 1001 www", "Failed to add www user"
        
      
          puts "        Make nginx root"
          mkdir_p "#{@guest.deploy_path}#{@model.www_root}"
      
          if @model.delayed_jobs_supported
            puts "        Write Delayed::Jobs systemd"
            render_to_remote "/cloud_model/guest/etc/systemd/system/delayed_jobs.service", "#{@guest.deploy_path}/etc/systemd/system/delayed_jobs.service", guest: @guest, model: @model      
            chroot! @guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs.service /etc/systemd/system/multi-user.target.wants/delayed_jobs.service", "Failed to enable delayed_jobs service" 
          end
      
          if @model.ssl_supported?
            if @model.ssl_certbot?
              puts "        Write certbot systemd"
              mkdir_p overlay_path
              render_to_remote "/cloud_model/guest/etc/systemd/system/nginx.service.d/certbot_init.conf", "#{overlay_path}/certbot_init.conf", guest: @guest, model: @model      
              render_to_remote "/cloud_model/guest/etc/systemd/system/certbot-renew.service", "#{@guest.deploy_path}/etc/systemd/system/certbot-renew.service"    
              render_to_remote "/cloud_model/guest/etc/systemd/system/certbot-renew.timer", "#{@guest.deploy_path}/etc/systemd/system/certbot-renew.timer"    
              chroot! @guest.deploy_path, "ln -s /etc/systemd/system/certbot-renew.timer /etc/systemd/system/timers.target.wants/certbot-renew.timer", "Failed to enable certbot renew timer" 
            end
          
            puts "        Write SSL files"
            ssl_base_dir = File.expand_path("etc/nginx/ssl", @guest.deploy_path)
            mkdir_p ssl_base_dir
                  
            @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.crt", ssl_base_dir), 'w') do |f|
              f.write @model.ssl_cert.crt
            end
        
            @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.key", ssl_base_dir), 'w') do |f|
              f.write @model.ssl_cert.key
            end
        
            @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.ca.crt", ssl_base_dir), 'w') do |f|
              f.write @model.ssl_cert.ca
            end
                    
            host_source_dir = "/inst/hosts_by_ip/#{@guest.private_address}"
            ssh_host_key_source = "#{host_source_dir}/etc/nginx/ssl"
            key_file = File.expand_path("dhparam.pem", ssh_host_key_source)
            begin
              @host.sftp.lstat! key_file
            rescue Net::SFTP::StatusException => e
              mkdir_p ssh_host_key_source
              @host.exec! "openssl dhparam -out #{key_file.shellescape} 2048", 'Failed to generate dhparam keys'
            end         

            @host.exec! "cp -ra #{key_file.shellescape} #{ssl_base_dir.shellescape}", "Failed to copy dhparam keys"            
          end
       
          deploy_web_image
              
          @host.exec "chmod -R 2775 #{@guest.deploy_path}#{@model.www_root}"
          @host.exec "chown -R 101001:101001 #{@guest.deploy_path}#{@model.www_root}"
          @host.exec "chown -R 100000:100000 #{@guest.deploy_path}/etc/nginx/ssl #{@guest.deploy_path}/etc/default/rails"
        
          log_dir_path = "/var/log/nginx"
          mkdir_p "#{@guest.deploy_path}#{log_dir_path}"
          @host.exec  "chmod -R 2770 #{@guest.deploy_path}#{log_dir_path}"
          @host.exec  "chown -R 101001:101001 #{@guest.deploy_path}#{log_dir_path}"
        end
    
        def auto_restart
          true
        end
      
        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/nginx.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf", guest: @guest, model: @model
          @host.exec  "chown -R 100000:100000 #{overlay_path}"
          # TODO: Resolve dependencies
          # Services::Ssh.new(@host, @options).write_config
        
          if @model.daily_rake_task
            render_to_remote "/cloud_model/guest/etc/systemd/system/rake@.service", "#{@guest.deploy_path}/etc/systemd/system/rake@.service"
            render_to_remote "/cloud_model/guest/etc/systemd/system/rake@.timer", "#{@guest.deploy_path}/etc/systemd/system/rake@.timer"
            mkdir_p "#{@guest.deploy_path}/etc/systemd/system/timers.target.wants"
            chroot @guest.deploy_path, "ln -s /etc/systemd/system/rake@.timer /etc/systemd/system/timers.target.wants/rake@#{@model.daily_rake_task.shellescape}.timer"
            @host.exec "chown -R 100000:100000 #{@guest.deploy_path}/etc/systemd/system/rake@.service #{@guest.deploy_path}/etc/systemd/system/rake@.timer"
          end
        
          super        
        end
      end
    end
  end
end