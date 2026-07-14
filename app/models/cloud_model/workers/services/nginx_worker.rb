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

        # LXD disk-device name the web-app volume is attached under.
        WEB_DEVICE = 'webapp'

        # ZFS dataset / host mountpoint of a guest's web-app clone for one
        # deploy. Timestamped so a redeploy's new clone can be attached before
        # the previous one is destroyed.
        def web_clone_dataset deploy_id
          "guests/web/#{@guest.name}-#{deploy_id}"
        end

        def web_clone_mount deploy_id
          "/cloud/web/#{@guest.name}-#{deploy_id}"
        end

        # Writes the per-guest runtime config into an already-populated app tree
        # (the cloned artifact). No unpacking any more — the code is the ZFS
        # clone; only the instance-specific config is layered on. The host app
        # (core-admin) prepends further writes via `super deploy_path`.
        def unroll_web_image deploy_path
          return false unless @model.deploy_web_image

          comment_sub_step "Configure WebImage #{@model.deploy_web_image.name} in #{deploy_path}"
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

        # LXD disk-device name for a release (unique per deploy so a new release
        # can be attached while the previous one is still mounted).
        def web_device deploy_id
          "#{WEB_DEVICE}-#{deploy_id}"
        end

        # Clones the web image's @ready artifact for this guest's (template,
        # arch) into a fresh dataset, writes the per-guest config into it,
        # attaches it under releases/<id>, and hands over via the `current`
        # symlink — the Capistrano-style atomic swap (no request ever sees a
        # missing document root). Shared by the offline guest deploy and the
        # live redeploy. Returns the deploy id.
        def provision_web_volume online:
          web_image = @model.deploy_web_image
          template = @guest.template
          arch = @host.arch

          web_image.ensure_web_volume! @host, template, arch

          deploy_id = make_deploy_web_image_id
          dataset = web_clone_dataset deploy_id
          mount = web_clone_mount deploy_id

          comment_sub_step "Clone WebImage #{web_image.name} for #{@guest.name}"
          @host.exec! "zfs destroy -r #{dataset.shellescape}" if @host.exec("zfs list #{dataset.shellescape}").first
          @host.exec! "zfs clone -p -o mountpoint=#{mount.shellescape} -o compression=#{CloudModel.config.zfs_compression.shellescape} #{web_image.build_snapshot(template, arch).shellescape} #{dataset.shellescape}",
            "Failed to clone web image #{web_image.name}"

          strip_web_release mount

          # The clone IS the Rails root; only the instance config is layered on.
          unroll_web_image mount
          # Own the whole clone as the container's www user (unprivileged LXD
          # maps host 101001 → container 1001), so the raw disk device needs no
          # id-shifting and Passenger can read/write immediately.
          @host.exec! "chown -R 101001:101001 #{mount.shellescape}", "Failed to own web app volume"

          attach_web_release deploy_id, mount
          activate_web_release deploy_id, online: online
          cleanup_old_web_releases deploy_id, online: online
          deploy_id
        end

        # Slims a fresh deploy clone — the ZFS-clone equivalent of the old
        # tarball PACKAGE_EXCLUDES. The workspace snapshot keeps this scratch for
        # incremental rebuilds; each per-guest clone drops it here. Runtime
        # output stays: public/vite, public/assets, the compiled .so in each
        # gem's lib/, node_modules, and .cache/puppeteer (Chromium).
        def strip_web_release mount
          comment_sub_step "Strip build artifacts from release"
          # Anchored globs only — NEVER a bare `-name cache`/`-name doc`, which
          # would also delete runtime code (e.g. activesupport's own
          # lib/active_support/cache/coder.rb) and break the app. Mirrors the
          # old tarball PACKAGE_EXCLUDES.
          @host.exec "cd #{mount.shellescape} && " \
            "rm -rf .git .gitignore .rspec tmp log spec test features doc .playwright-mcp vendor/cache solr; " \
            "rm -f db/*.sqlite3 gems/*.zip; " \
            "rm -rf bundle/ruby/*/cache bundle/ruby/*/doc; " \
            "rm -rf bundle/ruby/*/bundler/gems/*/.git; " \
            "rm -rf bundle/ruby/*/gems/*/ext/*/target bundle/ruby/*/bundler/gems/*/ext/*/target; " \
            "true"
        end

        # Attaches the cloned release read/write at releases/<id> in the container.
        def attach_web_release deploy_id, mount
          release_path = "#{@model.www_root}/releases/#{deploy_id}"
          @host.exec! "lxc config device add #{@lxc.name.shellescape} #{web_device(deploy_id)} disk source=#{mount.shellescape} path=#{release_path.shellescape}",
            "Failed to attach web release"
        end

        # Points `current` at the new release. `ln -sfn` replaces the symlink in
        # place (atomic rename), so the handover has no window — exactly the
        # Capistrano `current -> releases/<ts>` scheme. Live containers get it
        # via `lxc exec`; an offline guest deploy writes it into the rootfs (the
        # device mounts on start).
        def activate_web_release deploy_id, online:
          release_path = "#{@model.www_root}/releases/#{deploy_id}"
          if online
            @model.guest.exec! "/bin/mkdir -p #{@model.www_root}/releases", "Failed to make releases dir"
            @model.guest.exec! "/bin/ln -sfn #{release_path.shellescape} #{@model.www_root}/current", "Failed to activate release"
          else
            rootfs_www = "#{@guest.deploy_path}#{@model.www_root}"
            @host.exec! "mkdir -p #{rootfs_www.shellescape}/releases", "Failed to make releases dir"
            @host.exec! "ln -sfn #{release_path.shellescape} #{rootfs_www.shellescape}/current", "Failed to activate release"
          end
        end

        # Detaches stale release devices (live container) and destroys the clones
        # of previous deploys, keeping only the release now pointed at by current.
        def cleanup_old_web_releases current_deploy_id, online:
          keep_dataset = web_clone_dataset current_deploy_id
          keep_device = web_device current_deploy_id

          if online
            success, devices = @host.exec "lxc config device list #{@lxc.name.shellescape}"
            if success
              devices.to_s.split("\n").map(&:strip).each do |dev|
                next unless dev.start_with? "#{WEB_DEVICE}-"
                next if dev == keep_device
                @host.exec "lxc config device remove #{@lxc.name.shellescape} #{dev.shellescape}"
              end
            end
          end

          success, list = @host.exec "zfs list -H -o name -r guests/web"
          if success
            list.to_s.split("\n").each do |dataset|
              next unless dataset =~ %r{\Aguests/web/#{Regexp.escape(@guest.name)}-\d+\z}
              next if dataset == keep_dataset
              @host.exec "zfs destroy -r #{dataset.shellescape}"
            end
          end
        end

        def deploy_web_image
          provision_web_volume online: false if @model.deploy_web_image
        end

        def redeploy_web_image options={}
          return false unless options[:force] or (@model.deploy_web_image and @model.redeploy_web_image_state == :pending)

          @model.update_attributes redeploy_web_image_state: :running, redeploy_web_image_last_issue: nil, redeploy_web_image_step: 'transfer'
          web_image = @model.deploy_web_image
          web_image.try :append_to_build_log, "Deploying to #{@guest.name} (#{@guest.host.name})…\n"

          comment_sub_step "Deploy to #{@guest.name}: #{@model.name}"
          begin
            # Clone the freshly-built artifact, layer per-guest config, attach it
            # as a new release and hand over via the current symlink.
            provision_web_volume online: true

            # Passenger resolved the OLD current at startup; the symlink swap
            # alone won't move a running app group. Restart it explicitly; fall
            # back to an nginx restart (short blip, deterministic) when
            # passenger-config is not available.
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

            if @model.ssl_certbot?
              # Certbot manages the cert — never preinstall a managed one.
              # Write a self-signed bootstrap cert so nginx can start at all
              # (no ssl listener without cert files, and without a running
              # nginx no ACME challenge); certbot replaces it via
              # ExecStartPost (certbot_init.conf) on first start.
              comment_sub_step "Generate self-signed bootstrap cert for certbot"
              hostname = @guest.external_hostname.shellescape
              chroot! @guest.deploy_path,
                "openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -days 30 " \
                "-subj '/CN=#{hostname}' " \
                "-keyout /etc/nginx/ssl/#{hostname}.key -out /etc/nginx/ssl/#{hostname}.crt",
                "Failed to generate bootstrap cert"
            elsif @model.ssl_cert
              @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.crt", ssl_base_dir), 'w') do |f|
                f.write @model.ssl_cert.crt
              end

              @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.key", ssl_base_dir), 'w') do |f|
                f.write @model.ssl_cert.key
              end

              @host.sftp.file.open(File.expand_path("#{@guest.external_hostname}.ca.crt", ssl_base_dir), 'w') do |f|
                f.write @model.ssl_cert.ca
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
          # Hash what THIS deploy wrote: a fresh container never has the
          # certbot cert yet, so the config was rendered with the bootstrap.
          write_config_manifest config_sync_plan(certbot_cert_available: false)
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
        def config_sync_plan certbot_cert_available: nil
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

          certbot_cert = certbot_cert_available.nil? ? certbot_cert_available? : certbot_cert_available
          files.each do |file|
            # upload_to_guest/render_to_remote write via IO#puts — hash the
            # content as it lands on disk (with trailing newline).
            content = render file[:template], guest: @guest, model: @model, certbot_cert_available: certbot_cert
            content += "\n" unless content.end_with? "\n"
            file[:content] = content
            file[:hash] = Digest::SHA256.hexdigest content
          end
        end

        # Certbot manages its cert under /etc/letsencrypt on the RUNNING
        # guest — when it is already there, the rendered config references it
        # directly instead of the self-signed bootstrap (which only exists so
        # a fresh nginx can start and answer the ACME challenge).
        def certbot_cert_available?
          return false unless @model.ssl_certbot?
          success, _out = guest_sh "test -f /etc/letsencrypt/live/#{@guest.external_hostname.shellescape}/fullchain.pem"
          !!success
        rescue => e
          Rails.logger.warn "Could not check for certbot cert: #{e.message}"
          false
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
            bak = backup_path(file[:path]).shellescape
            guest_sh "if [ -f #{file[:path].shellescape} ]; then mkdir -p $(dirname #{bak}) && cp -a #{file[:path].shellescape} #{bak}; fi"
            upload_to_guest file[:content], file[:path]
          end

          success, output = guest_sh 'nginx -t 2>&1'
          unless success
            to_write.each do |file|
              bak = backup_path(file[:path]).shellescape
              guest_sh "if [ -f #{bak} ]; then mv #{bak} #{file[:path].shellescape}; else rm -f #{file[:path].shellescape}; fi"
            end
            return {state: :failed, applied: [], blocked: [], output: output}
          end

          success, output = guest_sh 'systemctl reload nginx 2>&1'
          unless success
            return {state: :failed, applied: [], blocked: [], output: output}
          end

          to_write.each { |file| guest_sh "rm -f #{backup_path(file[:path]).shellescape}" }
          write_config_manifest plan
          {state: :applied, applied: to_write.map { |f| f[:path] }, blocked: []}
        end

        # Rollback copies must live OUTSIDE the config directories nginx
        # includes — cloudmodel.conf pulls in server.d/* (any suffix), so an
        # in-place .cm-bak neighbour would itself break `nginx -t` with
        # duplicate locations.
        def backup_path path
          "/var/lib/cloud_model/nginx_bak#{path}"
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