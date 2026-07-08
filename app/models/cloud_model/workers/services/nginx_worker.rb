require 'stringio'
require 'securerandom'

module CloudModel
  module Workers
    module Services
      # Worker that configures the nginx service inside a guest container.
      #
      # Handles the full nginx setup: renders `nginx.conf` and the virtual host
      # config, deploys a {CloudModel::WebImage} (tar-unpacking into a timestamped
      # directory and symlinking `current`), deploys web locations (web apps with
      # their config files and systemd units), and writes SSL certificates + DH
      # params. Also manages Capistrano-style Delayed::Job queues and SSH
      # `authorized_keys` for the `www` user.
      class NginxWorker < CloudModel::Workers::Services::BaseWorker

        def web_image_cache_dir
          "/var/cache/cloud_model/web_images"
        end

        # Tarball cached on the host, keyed by web image id + GridFS file id, so a
        # rebuilt image (new file_id) misses the cache and is re-fetched.
        def web_image_cache_file
          image = @model.deploy_web_image
          "#{web_image_cache_dir}/#{image.id}-#{image.file_id}.tar"
        end

        # Ensure the current web image tarball is present on the host, loading it
        # from GridFS (and uploading it) only once per host and image version.
        # Returns the on-host cache path.
        def ensure_web_image_cached_on_host
          image = @model.deploy_web_image
          cache_file = web_image_cache_file

          return cache_file if @host.exec("test -f #{cache_file.shellescape}")&.first

          comment_sub_step "Cache WebImage #{image.name} on host"
          mkdir_p web_image_cache_dir
          # Keep only the current version of this image on the host.
          @host.exec "rm -f #{web_image_cache_dir}/#{image.id}-*.tar"
          io = StringIO.new(image.file.data)
          @host.sftp.upload!(io, cache_file)

          cache_file
        end

        def unroll_web_image deploy_path
          return false unless @model.deploy_web_image

          mkdir_p deploy_path

          comment_sub_step "Unroll WebImage #{@model.deploy_web_image.name} to #{deploy_path}"
          cache_file = ensure_web_image_cached_on_host
          @host.exec "cd #{deploy_path} && tar xpf #{cache_file.shellescape}"

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

          if @model.deploy_web_image.master_key
            @host.exec! "echo -n '#{@model.deploy_web_image.master_key}' >#{deploy_path}/config/master.key", "Failed to set master key"
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

          @model.update_attributes redeploy_web_image_state: :running, redeploy_web_image_last_issue: nil, redeploy_web_image_step: 'unroll'
          web_image = @model.deploy_web_image
          web_image.try :append_to_build_log, "Deploying to #{@guest.name} (#{@guest.host.name})…\n"

          comment_sub_step "Deploy to #{@guest.name}: #{@model.name}"
          begin
            deploy_id = make_deploy_web_image_id
            unroll_path = "/tmp/webimage_unroll_#{@model.id}"
            deploy_path = "#{unroll_path}#{@model.www_root}/#{deploy_id}"

            @host.exec! "rm -rf #{unroll_path}", "Failed to clean unroll path"
            mkdir_p deploy_path
            unroll_web_image deploy_path

            @model.update_attribute :redeploy_web_image_step, 'transfer'
            comment_sub_step "Copy unrolled data to guest"
            @host.exec! "cd #{unroll_path} && tar c . | lxc exec #{@model.guest.current_lxd_container.name.shellescape} -- /bin/tar x -C / --no-same-owner", "Failed to transfer files"

            comment_sub_step "Remove unrolled data from hosts /tmp"
            @host.exec "rm -rf #{unroll_path}"

            @model.update_attribute :redeploy_web_image_step, 'permissions'
            comment_sub_step "Align owner of guest data"
            @model.guest.exec! "/bin/chown -R www:www #{@model.www_root}/#{deploy_id}", "Failed to set user to www "

            @model.update_attribute :redeploy_web_image_step, 'activate'
            @model.guest.exec! "/bin/rm -f #{@model.www_root}/current", "Failed to remove old current"
            @model.guest.exec! "/bin/ln -s #{@model.www_root}/#{deploy_id} #{@model.www_root}/current", "Failed to set current"
            @model.guest.exec! "/bin/touch #{@model.www_root}/current/tmp/restart.txt", "Failed to restart service"

            # The touch alone is unreliable: the running Passenger app group
            # resolved the current symlink at startup and watches restart.txt
            # in the OLD target dir — the old code keeps serving. Restart the
            # app explicitly; fall back to an nginx restart (short blip, but
            # deterministic) when passenger-config is not available.
            @model.update_attribute :redeploy_web_image_step, 'restart'
            comment_sub_step "Restart web application"
            web_image.try :append_to_build_log, "Restarting app on #{@guest.name}…\n"
            success, _out = @model.guest.exec "/usr/local/rvm/bin/rvm default do passenger-config restart-app #{@model.www_root.shellescape} --ignore-app-not-running"
            unless success
              @model.guest.exec! "/bin/systemctl restart nginx", "Failed to restart nginx"
            end
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
            web_image.try :append_to_build_log, "FAILED: #{@guest.name}: #{e}\n"
            @model.update_attributes redeploy_web_image_state: :failed, redeploy_web_image_last_issue: "#{e}"
            return false
          end
          web_image.try :append_to_build_log, "#{@guest.name} done\n"
          @model.update_attributes redeploy_web_image_state: :finished, redeploy_web_image_step: 'done'
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
          render_to_guest "/cloud_model/guest/etc/nginx/sites-available/cloudmodel.conf", "/etc/nginx/sites-available/cloudmodel.conf", 0600, guest: @guest, model: @model
          #render_to_guest "/cloud_model/guest/etc/nginx/conf.d/gzip.conf", "/etc/nginx/conf.d/gzip.conf", 0600, guest: @guest, model: @model

          chroot @guest.deploy_path, "ln -s /etc/nginx/sites-available/cloudmodel.conf etc/nginx/sites-enabled/cloudmodel.conf"

          chroot! @guest.deploy_path, "groupadd -f -r -g 1001 www && id -u www || useradd -c 'added by cloud_model for nginx' -d /var/www -s /bin/bash -r -g 1001 -u 1001 www", "Failed to add www user"

          comment_sub_step "Make nginx root"
          mkdir_p "#{@guest.deploy_path}#{@model.www_root}"

          # App Stuff
          # TODO: Move to web locations
          mkdir_p "#{@guest.deploy_path}/etc/nginx/server.d"
          if @model.web_locations.where(location: '/').count == 0
            if @model.reverse_proxy_supported?
              render_to_remote "/cloud_model/guest/etc/nginx/server.d/proxy.conf", "#{@guest.deploy_path}/etc/nginx/server.d/proxy.conf", guest: @guest, model: @model
            elsif @model.passenger_supported?
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

            if @model.ssl_cert
              @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.crt", ssl_base_dir), 'w') do |f|
                f.write @model.ssl_cert.crt
              end

              @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.key", ssl_base_dir), 'w') do |f|
                f.write @model.ssl_cert.key
              end

              @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.ca.crt", ssl_base_dir), 'w') do |f|
                f.write @model.ssl_cert.ca
              end
            elsif @model.ssl_certbot?
              # No cert record needed with certbot: write a self-signed
              # bootstrap cert so nginx can start; certbot replaces it via
              # ExecStartPost (certbot_init.conf) on first start.
              comment_sub_step "Generate self-signed bootstrap cert for certbot"
              hostname = @guest.external_hostname.shellescape
              chroot! @guest.deploy_path,
                "openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 " \
                "-subj '/CN=#{hostname}' " \
                "-keyout /etc/nginx/ssl/#{hostname}.key -out /etc/nginx/ssl/#{hostname}.crt",
                "Failed to generate bootstrap cert"
              @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.ca.crt", ssl_base_dir), 'w') do |f|
                f.write ''
              end
            else
              raise "nginx service '#{@model.name}' has ssl_supported but neither ssl_cert nor ssl_certbot set"
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

          # Baseline for later live syncs: record what was deployed, so
          # sync_config can tell manual edits on the guest from drift.
          write_config_baseline_manifest
        end

        # Best-effort bookkeeping — a failed manifest write must never fail
        # the deploy; the next sync then reports the files as unrecorded.
        def write_config_baseline_manifest
          write_config_manifest config_sync_plan
        rescue => e
          Rails.logger.warn "Could not write nginx config manifest: #{e.message}"
        end

        # Hash manifest of the last written nginx configs, kept on the guest.
        # sync_config compares the live files against it to detect manual
        # edits before overwriting anything.
        CONFIG_MANIFEST_PATH = '/etc/nginx/.cloudmodel_manifest.json'

        # The files a live config sync manages — the same set write_config
        # renders. Deploy-only artefacts (web app location confs, systemd
        # units, SSL files, …) are deliberately not part of this.
        # @return [Array<Hash>] {template:, path:, content:, hash:}
        def config_sync_plan
          files = [
            {template: '/cloud_model/guest/etc/nginx/nginx.conf', path: '/etc/nginx/nginx.conf'},
            {template: '/cloud_model/guest/etc/nginx/sites-available/cloudmodel.conf', path: '/etc/nginx/sites-available/cloudmodel.conf'}
          ]
          if @model.web_locations.where(location: '/').count == 0
            if @model.reverse_proxy_supported?
              files << {template: '/cloud_model/guest/etc/nginx/server.d/proxy.conf', path: '/etc/nginx/server.d/proxy.conf'}
            elsif @model.passenger_supported?
              files << {template: '/cloud_model/guest/etc/nginx/server.d/passenger.conf', path: '/etc/nginx/server.d/passenger.conf'}
            elsif @model.capistrano_supported?
              files << {template: '/cloud_model/guest/etc/nginx/server.d/cap-deployed.conf', path: '/etc/nginx/server.d/cap-deployed.conf'}
            end
          end

          files.each do |file|
            # upload_to_guest/render_to_remote write via IO#puts — hash the
            # content as it lands on disk (with trailing newline).
            content = render file[:template], guest: @guest, model: @model
            content += "\n" unless content.end_with? "\n"
            file[:content] = content
            file[:hash] = Digest::SHA256.hexdigest content
          end
        end

        # Push the current nginx config to the RUNNING container without a
        # redeploy. Refuses to touch files that differ from the recorded
        # manifest (manually edited or never recorded) unless force is given.
        # Validates with `nginx -t` — on failure the previous files are
        # restored — and reloads nginx only when files actually changed.
        #
        # @param force [Boolean] overwrite manually edited/unrecorded files
        # @return [Hash] {state: :applied|:unchanged|:blocked|:failed,
        #   applied: [paths], blocked: [{path:, reason:}], output: String}
        def sync_config force: false
          manifest = read_config_manifest
          plan = config_sync_plan.each do |file|
            remote = remote_file_hash file[:path]
            file[:state] = if remote.nil?
              :missing # not on the guest yet -> just write it
            elsif remote == file[:hash]
              :unchanged
            elsif manifest[file[:path]].nil?
              :unrecorded # pre-manifest deploy -> unknown provenance
            elsif remote != manifest[file[:path]]
              :edited # manually changed on the guest
            else
              :changed
            end
          end

          blocked = plan.select { |f| [:edited, :unrecorded].include? f[:state] }
          if blocked.any? && !force
            return {state: :blocked, applied: [],
                    blocked: blocked.map { |f| {path: f[:path], reason: f[:state]} }}
          end

          to_write = plan.reject { |f| f[:state] == :unchanged }
          if to_write.empty?
            write_config_manifest plan
            return {state: :unchanged, applied: [], blocked: []}
          end

          to_write.each do |file|
            guest_sh "if [ -f #{file[:path].shellescape} ]; then cp -a #{file[:path].shellescape} #{file[:path].shellescape}.cm-bak; fi"
            upload_to_guest file[:content], file[:path]
          end

          success, output = guest_sh 'nginx -t 2>&1'
          unless success
            to_write.each do |file|
              guest_sh "if [ -f #{file[:path].shellescape}.cm-bak ]; then mv #{file[:path].shellescape}.cm-bak #{file[:path].shellescape}; else rm -f #{file[:path].shellescape}; fi"
            end
            return {state: :failed, applied: [], blocked: [], output: output}
          end

          success, output = guest_sh 'systemctl reload nginx 2>&1'
          unless success
            return {state: :failed, applied: [], blocked: [], output: output}
          end

          to_write.each { |file| guest_sh "rm -f #{file[:path].shellescape}.cm-bak" }
          write_config_manifest plan
          {state: :applied, applied: to_write.map { |f| f[:path] }, blocked: []}
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

        private

        # Run a shell line inside the container — plain @guest.exec would let
        # the HOST shell interpret operators like `&&` after `lxc exec` ends.
        def guest_sh command
          @guest.exec "sh -c #{command.shellescape}"
        end

        # @return [String, nil] SHA256 of the file on the guest, nil if absent
        def remote_file_hash path
          success, output = guest_sh "sha256sum #{path.shellescape}"
          return nil unless success
          output.split(' ').first
        end

        # @return [Hash{String => String}] path => sha256 of the last write
        def read_config_manifest
          success, output = guest_sh "cat #{CONFIG_MANIFEST_PATH.shellescape}"
          return {} unless success
          JSON.parse output
        rescue JSON::ParserError
          {}
        end

        def write_config_manifest plan
          manifest = plan.to_h { |file| [file[:path], file[:hash]] }
          upload_to_guest JSON.pretty_generate(manifest), CONFIG_MANIFEST_PATH
        end
      end
    end
  end
end