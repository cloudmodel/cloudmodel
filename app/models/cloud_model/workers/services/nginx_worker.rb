require 'stringio'
require 'securerandom'

module CloudModel
  module Workers
    module Services
      class NginxWorker < CloudModel::Workers::Services::BaseWorker

        def unroll_web_image deploy_path
          return false unless @model.deploy_web_image

          mkdir_p deploy_path

          comment_sub_step "Unroll WebImage #{@model.deploy_web_image.name} to #{deploy_path}"
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

          comment_sub_step "Deploy to #{@guest.name}: #{@model.name}"
          begin
            deploy_id = make_deploy_web_image_id
            unroll_path = "/tmp/webimage_unroll_#{@model.id}"
            deploy_path = "#{unroll_path}#{@model.www_root}/#{deploy_id}"

            @host.exec! "rm -rf #{unroll_path}", "Failed to clean unroll path"
            mkdir_p deploy_path
            unroll_web_image deploy_path

            comment_sub_step "Copy unrolled data to guest"
            @host.exec! "cd #{unroll_path} && tar c . | lxc exec #{@model.guest.current_lxd_container.name.shellescape} -- /bin/tar x -C / --no-same-owner", "Failed to transfer files"

            comment_sub_step "Remove unrolled data from hosts /tmp"
            @host.exec "rm -rf #{unroll_path}"

            comment_sub_step "Align owner of guest data"
            @model.guest.exec! "/bin/chown -R www:www #{@model.www_root}/#{deploy_id}", "Failed to set user to www "

            @model.guest.exec! "/bin/rm -f #{@model.www_root}/current", "Failed to remove old current"
            @model.guest.exec! "/bin/ln -s #{@model.www_root}/#{deploy_id} #{@model.www_root}/current", "Failed to set current"
            @model.guest.exec! "/bin/touch #{@model.www_root}/current/tmp/restart.txt", "Failed to restart service"
            if @model.delayed_jobs_supported
              @model.delayed_jobs_queues.each do |q|
                # Stop delayed job if used
                comment_sub_step "Restarting delayed job queue #{q}"
                command = "/bin/systemctl restart delayed_jobs@#{q.shellescape}"
                #puts command
                success, data = @model.guest.exec command
                unless success
                  puts "Error restarting delayed job queue #{q}: #{data}"
                end
              end
            end
          rescue Exception => e
            CloudModel.log_exception e
            @model.update_attributes redeploy_web_image_state: :failed, redeploy_web_image_last_issue: "#{e}"
            return false
          end
          @model.update_attributes redeploy_web_image_state: :finished
        end

        def deploy_web_locations
          @model.web_locations.each do |web_location|
            comment_sub_step "Deploy #{web_location.web_app.to_s}"
            increase_indent

            mkdir_p "#{@guest.deploy_path}/opt/web-app"

            web_app = web_location.web_app
            web_app_class = web_app.class

            # TODO: Fetch/Config per location; For now it only supports one instance of WebApp per Guest
            if app_folder = web_app_class.app_folder
              if fetch_command = web_app_class.fetch_app_command
                comment_sub_step "Fetch #{web_app_class.app_name}"
                chroot! @guest.deploy_path, fetch_command, "Failed to download #{web_app_class.app_name}"
              end
            end

            # Systemd Config
            # TODO: Render init db user script + systemd prestart if exists
            # TODO: Call app init db script on systemd prestart if exists
            # TODO: Make and populate persistant folders on systemd prestart

            # Render nginx conf if exists
            mkdir_p "#{@guest.deploy_path}/etc/nginx/server.d"
            if template_exists?("/#{web_app_class.name.underscore}/nginx.conf")
              comment_sub_step "Render app nginx.conf"
              render_to_remote "/#{web_app_class.name.underscore}/nginx.conf", "#{@guest.deploy_path}/etc/nginx/server.d/#{web_app_class.app_name}-#{web_app.name.underscore.gsub(' ', '_')}.conf", guest: @guest, service: @model, model: web_location
            end

            # Render config files
            web_app.config_files_to_render.each do |src, dst|
              comment_sub_step "Render config #{src}"
              remote_file = "#{@guest.deploy_path}#{dst[0]}"
              render_to_remote src, remote_file, dst[1], guest: @guest, service: @model, web_location: web_location, model: web_app
              if dst[2]
                uid = dst[2][:uid] || 100000
                gid = dst[2][:gid] || 100000
                host.exec! "chown -R #{uid}:#{gid} #{remote_file}", "failed to set owner for #{remote_file}"
              end
            end

            web_app.configure.each do |configure_cmd|
              comment_sub_step "Config to #{configure_cmd[1]}"
              chroot! @guest.deploy_path, configure_cmd[0], "Failed to #{configure_cmd[1]}"
            end

            decrease_indent
          end
        end

        def write_config
          comment_sub_step "Config nginx"

          render_to_guest "/cloud_model/guest/etc/nginx/nginx.conf", "/etc/nginx/nginx.conf", 0600, guest: @guest, model: @model

          chroot! @guest.deploy_path, "groupadd -f -r -g 1001 www && id -u www || useradd -c 'added by cloud_model for nginx' -d /var/www -s /bin/bash -r -g 1001 -u 1001 www", "Failed to add www user"

          comment_sub_step "Make nginx root"
          mkdir_p "#{@guest.deploy_path}#{@model.www_root}"

          # App Stuff
          # TODO: Move to web locations
          mkdir_p "#{@guest.deploy_path}/etc/nginx/server.d"
          if @model.web_locations.where(location: '/').count == 0
            if @model.passenger_supported?
              render_to_remote "/cloud_model/guest/etc/nginx/server.d/passenger.conf", "#{@guest.deploy_path}/etc/nginx/server.d/passenger.conf", guest: @guest, model: @model
              render_to_remote "/cloud_model/guest/etc/default/rails", "#{@guest.deploy_path}/etc/default/rails", guest: @guest, model: @model
            elsif @model.capistrano_supported?
              render_to_remote "/cloud_model/guest/etc/nginx/server.d/cap-deployed.conf", "#{@guest.deploy_path}/etc/nginx/server.d/cap-deployed.conf", guest: @guest, model: @model
            end
          end

          if @model.delayed_jobs_supported
            comment_sub_step "Write Delayed::Jobs systemd"
            render_to_remote "/cloud_model/guest/etc/systemd/system/delayed_jobs@.service", "#{@guest.deploy_path}/etc/systemd/system/delayed_jobs@.service", guest: @guest, model: @model
            @model.delayed_jobs_queues.each do |q|
              chroot! @guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs@.service /etc/systemd/system/multi-user.target.wants/delayed_jobs@#{q.shellescape}.service", "Failed to enable delayed_jobs service for queue #{q}"
            end
          end


          deploy_web_image

          # Web Locations
          deploy_web_locations

          # SSL Stuff
          if @model.ssl_supported?
            if @model.ssl_certbot?
              comment_sub_step "Write certbot systemd"
              mkdir_p overlay_path
              render_to_remote "/cloud_model/guest/etc/systemd/system/nginx.service.d/certbot_init.conf", "#{overlay_path}/certbot_init.conf", guest: @guest, model: @model
              render_to_remote "/cloud_model/guest/etc/systemd/system/certbot-renew.service", "#{@guest.deploy_path}/etc/systemd/system/certbot-renew.service"
              render_to_remote "/cloud_model/guest/etc/systemd/system/certbot-renew.timer", "#{@guest.deploy_path}/etc/systemd/system/certbot-renew.timer"
              chroot! @guest.deploy_path, "ln -s /etc/systemd/system/certbot-renew.timer /etc/systemd/system/timers.target.wants/certbot-renew.timer", "Failed to enable certbot renew timer"
            end

            comment_sub_step "Write SSL files"
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

          if not @model.capistrano_ssh_groups.blank? #and @guest.has_service_type? CloudModel::Services::Ssh
            # Write authorized keys from database entries
            comment_sub_step "Write SSH authorized keys"
            ssh_dir = File.expand_path("var/www/.ssh", @guest.deploy_path)
            ssh_target = File.expand_path("authorized_keys", ssh_dir)
            mkdir_p "#{ssh_dir}"
            @host.exec "chown -R 101001:101001 #{ssh_dir}"
            @host.exec "rm -f #{ssh_target.shellescape}"

            puts ssh_target

            ssh_keys = []

            @model.capistrano_ssh_groups.each do |ssh_group|
              ssh_keys += ssh_group.pub_keys.map(&:key)
            end

            @host.sftp.file.open("#{ssh_target}", 'w') do |f|
              f.write ssh_keys.uniq * "\n"
            end
            @host.exec "chown -R 101001:101001 #{ssh_target}"
          end

          # Cleanup
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
          render_to_remote "/cloud_model/guest/etc/systemd/system/nginx.service.d/fix_perms.conf", "#{overlay_path}/fix_perms.conf", 644, guest: @guest, model: @model
          @host.exec  "chown -R 100000:100000 #{overlay_path}"
          # TODO: Resolve dependencies
          # Services::Ssh.new(@host, @options).write_config

          super
        end
      end
    end
  end
end