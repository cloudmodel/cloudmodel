module CloudModel
  module Workers
    module Services
      # Worker that configures the Jitsi Meet service inside a guest container.
      #
      # The {Components::JitsiComponentWorker} installs the full stack into the
      # template against a placeholder hostname. At deploy time this worker
      # applies the guest-specific branding (product name, provider, watermark
      # logo) to the pre-installed web UI.
      #
      # At deploy time this worker re-points the pre-installed stack from the
      # build placeholder hostname to the guest's real {Guest#external_hostname}
      # (prosody vhost, nginx site, config.js, jicofo/jvb properties + prosody
      # certs) and applies the guest-specific branding.
      class JitsiWorker < CloudModel::Workers::Services::BaseWorker
        WEB_ROOT = "/usr/share/jitsi-meet".freeze
        INTERFACE_CONFIG = "#{WEB_ROOT}/interface_config.js".freeze
        BUILD_HOSTNAME = CloudModel::Workers::Components::JitsiComponentWorker::BUILD_HOSTNAME

        def write_config
          repoint_domain
          apply_secure_domain
          apply_welcome_page

          comment_sub_step "Brand jitsi UI"

          if @model.watermark_svg
            upload_to_guest @model.watermark_svg, "#{WEB_ROOT}/images/watermark.svg", "0644"
            # The brand watermark shows the same uploaded logo
            set_interface_value "BRAND_WATERMARK_LINK", "images/watermark.svg"
          end

          set_interface_value "APP_NAME", @model.app_name if @model.app_name.present?
          set_interface_value "PROVIDER_NAME", @model.provider_name if @model.provider_name.present?
          set_interface_value "JITSI_WATERMARK_LINK", @model.watermark_link if @model.watermark_link.present?
          set_interface_value "DEFAULT_BACKGROUND", @model.default_background if @model.default_background.present?

          dedupe_nginx_directives
        end

        # Re-point the whole Jitsi stack from the build placeholder hostname to
        # the guest's real hostname. jitsi-meet bakes the domain into per-host
        # file NAMES (prosody vhost, web config.js, nginx site) and into the
        # CONTENTS of the prosody/jicofo/jvb/web configs, plus the prosody XMPP
        # certs. We rename the per-host files, rewrite every reference, and
        # regenerate the prosody certs for the new XMPP domains. Idempotent: a
        # second run finds nothing left to rename/replace.
        #
        # NOTE: exercised via a real Jitsi redeploy — the cert location can vary
        # by prosody/jitsi package version; adjust {regenerate_prosody_certs} if a
        # deploy shows prosody failing to load the new vhost cert.
        def repoint_domain
          old = BUILD_HOSTNAME
          new = @guest.external_hostname
          return if new.blank? || new == old

          comment_sub_step "Re-point jitsi #{old} -> #{new}"
          rename_host_files old, new
          rewrite_host_references old, new
          regenerate_prosody_certs new
          provision_service_accounts new
        end

        # Register jicofo's and jvb's XMPP accounts on the auth vhost with the
        # passwords the package wrote to its config files. The package postinst
        # does this itself on a live system, but in the template-build chroot
        # that registration does not survive — without the accounts jicofo
        # loops with SASL failures and every conference stays black.
        def provision_service_accounts new
          chroot! @guest.deploy_path, <<~SH, "Failed to provision jitsi service accounts"
            # jicofo: current packages keep the password in jicofo.conf
            # (client.password); older ones in /etc/jitsi/jicofo/config.
            FPW=$(sed -nE 's/^\\s*password: "(.*)"\\s*$/\\1/p' /etc/jitsi/jicofo/jicofo.conf 2>/dev/null | head -1)
            [ -n "$FPW" ] || FPW=$(sed -n 's/^JICOFO_AUTH_PASSWORD=//p' /etc/jitsi/jicofo/config 2>/dev/null)
            [ -n "$FPW" ] && prosodyctl register focus auth.#{new} "$FPW" </dev/null >/dev/null 2>&1 || true
            # jvb: xmpp-client shard PASSWORD in jvb.conf; older packages in
            # /etc/jitsi/videobridge/config.
            JPW=$(sed -nE 's/^\\s*PASSWORD="(.*)"\\s*$/\\1/p' /etc/jitsi/videobridge/jvb.conf 2>/dev/null | head -1)
            [ -n "$JPW" ] || JPW=$(sed -n 's/^JVB_AUTH_PASSWORD=//p' /etc/jitsi/videobridge/config 2>/dev/null)
            [ -n "$JPW" ] && prosodyctl register jvb auth.#{new} "$JPW" </dev/null >/dev/null 2>&1 || true
            # The focus client_proxy component only learns jicofo's sessions via
            # presence, which requires this roster subscription (the package
            # postinst does it on a live system) — without it every conference
            # request bounces with service-unavailable.
            timeout 60 prosodyctl mod_roster_command subscribe focus.#{new} focus@auth.#{new} </dev/null >/dev/null 2>&1 || true
            chown -R prosody:prosody /var/lib/prosody 2>/dev/null || true
          SH
        end

        # jitsi-meet's own nginx site re-declares `server_names_hash_bucket_size`
        # (and other http-context tunables) that cloudmodel already sets in its
        # global config. The duplicate makes `nginx -t` fail and nginx refuses to
        # start, so comment it out in the jitsi site(s) — identified by their
        # jitsi-meet web root — without touching cloudmodel's own config.
        def dedupe_nginx_directives
          chroot! @guest.deploy_path,
            "grep -rl '#{WEB_ROOT}' /etc/nginx/sites-available/ 2>/dev/null | " \
            "xargs -r sed -i 's/^\\s*server_names_hash_bucket_size/#&/' || true",
            "Failed to de-duplicate jitsi nginx directives"
        end

        def auto_restart
          true
        end

        # "Secure domain": only registered XMPP users may open a room; guests
        # join running rooms anonymously via a guest.<host> vhost. Mirrors the
        # canonical Jitsi secure-domain setup: prosody main vhost switches to
        # internal_hashed auth + a guest vhost is added, jicofo gets XMPP
        # authentication, and config.js advertises the anonymous guest domain.
        # All edits are idempotent (guarded by grep) so redeploys are stable.
        def apply_secure_domain
          return unless @model.secure_domain?
          host = @guest.external_hostname
          return if host.blank?

          comment_sub_step "Configure jitsi secure domain"

          prosody = "/etc/prosody/conf.avail/#{host}.cfg.lua"
          config  = "/etc/jitsi/meet/#{host}-config.js"
          jicofo  = "/etc/jitsi/jicofo/jicofo.conf"

          chroot! @guest.deploy_path, <<~SH, "Failed to configure jitsi secure domain"
            set -e
            # 1. main vhost: require registered users
            sed -i 's/authentication = "jitsi-anonymous"/authentication = "internal_hashed"/' #{prosody}
            # 2. anonymous guest vhost (inserted before the conference component)
            if ! grep -q 'VirtualHost "guest.#{host}"' #{prosody}; then
              sed -i '/^Component "conference.#{host}"/i VirtualHost "guest.#{host}"\\n    authentication = "anonymous"\\n    c2s_require_encryption = false\\n' #{prosody}
            fi
            # 3. only authenticated users create rooms
            if ! grep -q 'restrict_room_creation' #{prosody}; then
              sed -i '/^Component "conference.#{host}"/a\\    restrict_room_creation = true' #{prosody}
            fi
            # 4. web client: guests join via the anonymous domain (anchor on the
            # ACTIVE line only — the stock config carries a commented-out
            # anonymousdomain example that must not satisfy the guard)
            if ! grep -qE "^\\s*anonymousdomain:" #{config}; then
              sed -i "s|^\\(\\s*\\)domain: '#{host}',|\\1domain: '#{host}',\\n\\1anonymousdomain: 'guest.#{host}',|" #{config}
            fi
            # 5. jicofo: require XMPP authentication to open a room. The block
            # lives at jicofo.authentication (top level) — nested under xmpp it
            # parses but is silently ignored ("Authentication service disabled").
            if ! grep -q 'authentication:' #{jicofo}; then
              sed -i 's|^jicofo {|jicofo {\\n  authentication: {\\n    enabled: true\\n    type: XMPP\\n    login-url: "#{host}"\\n  }|' #{jicofo}
            fi
          SH

          provision_admin_user host
        end

        # Register the room-opening account. The container is rebuilt from the
        # template on every redeploy (prosody's account store lives inside), so
        # this runs each deploy; `register` writes the store directly, no
        # running prosody needed.
        def provision_admin_user host
          return if @model.admin_user.blank? || @model.admin_password.blank?
          require 'shellwords'
          user = @model.admin_user.shellescape
          pass = @model.admin_password.shellescape
          chroot! @guest.deploy_path,
            "prosodyctl register #{user} #{host} #{pass} </dev/null >/dev/null 2>&1 || true",
            "Failed to register jitsi admin user"
        end

        # Redirect the welcome page to an external URL (config.js
        # welcomePage.customUrl). Appended as a config override so the
        # package-managed block stays untouched; idempotent via marker.
        def apply_welcome_page
          return if @model.welcome_page_url.blank?
          host = @guest.external_hostname
          return if host.blank?
          config = "/etc/jitsi/meet/#{host}-config.js"
          url = @model.welcome_page_url.gsub("'") { "\\'" }
          chroot! @guest.deploy_path, <<~SH, "Failed to set jitsi welcome page"
            sed -i "/^config.welcomePage = /d" #{config}
            echo "config.welcomePage = { customUrl: '#{url}' };" >> #{config}
          SH
        end

        private

        # Rename the per-host files jitsi-meet created against the placeholder,
        # fixing the prosody conf.d and nginx sites-enabled symlinks.
        def rename_host_files old, new
          chroot! @guest.deploy_path, <<~SH, "Failed to rename jitsi per-host files"
            set -e
            # prosody virtual-host config
            if [ -f /etc/prosody/conf.avail/#{old}.cfg.lua ]; then
              mv -f /etc/prosody/conf.avail/#{old}.cfg.lua /etc/prosody/conf.avail/#{new}.cfg.lua
              rm -f /etc/prosody/conf.d/#{old}.cfg.lua
              ln -sf ../conf.avail/#{new}.cfg.lua /etc/prosody/conf.d/#{new}.cfg.lua
            fi
            # jitsi-meet web config + the package's self-signed web cert pair
            # (the nginx site references them by domain name)
            [ -f /etc/jitsi/meet/#{old}-config.js ] && mv -f /etc/jitsi/meet/#{old}-config.js /etc/jitsi/meet/#{new}-config.js || true
            for ext in crt key; do
              [ -f /etc/jitsi/meet/#{old}.$ext ] && mv -f /etc/jitsi/meet/#{old}.$ext /etc/jitsi/meet/#{new}.$ext || true
            done
            # Prefer the real certificate cloudmodel deployed for this guest (its
            # nginx service ssl_cert, written to /etc/nginx/ssl before services
            # are configured) over the package's self-signed one, so the web UI
            # serves a trusted cert. Symlink so later cert renewals stay live.
            if [ -f /etc/nginx/ssl/#{new}.crt ] && [ -f /etc/nginx/ssl/#{new}.key ]; then
              ln -sf /etc/nginx/ssl/#{new}.crt /etc/jitsi/meet/#{new}.crt
              ln -sf /etc/nginx/ssl/#{new}.key /etc/jitsi/meet/#{new}.key
            fi
            # nginx site
            if [ -f /etc/nginx/sites-available/#{old}.conf ]; then
              mv -f /etc/nginx/sites-available/#{old}.conf /etc/nginx/sites-available/#{new}.conf
              rm -f /etc/nginx/sites-enabled/#{old}.conf
              ln -sf ../sites-available/#{new}.conf /etc/nginx/sites-enabled/#{new}.conf
            fi
            # prosody datastore dirs (URL-encoded hostnames): carries the
            # focus/jvb service accounts — registered at package install under
            # the placeholder auth domain — over to the new domain, passwords
            # intact. Without this jicofo loops with failed logins (JID=null).
            for pre in "" "auth." "guest."; do
              o="/var/lib/prosody/$(echo "$pre#{old}" | sed 's/\\./%2e/g')"
              n="/var/lib/prosody/$(echo "$pre#{new}" | sed 's/\\./%2e/g')"
              [ -d "$o" ] && [ ! -d "$n" ] && mv "$o" "$n" || true
            done
          SH
        end

        # Replace every reference to the placeholder hostname across the prosody,
        # jitsi (jicofo/jvb/web) and nginx config trees. Dots are escaped so the
        # distinctive placeholder is matched literally.
        def rewrite_host_references old, new
          old_re = old.gsub(".", "\\.")
          chroot! @guest.deploy_path,
            "grep -rlF '#{old}' /etc/prosody /etc/jitsi /etc/nginx 2>/dev/null | " \
            "xargs -r sed -i 's/#{old_re}/#{new}/g' || true",
            "Failed to rewrite jitsi hostname references"
        end

        # Prosody references self-signed certs named after the XMPP domains
        # (`<host>` and `auth.<host>`); after the rename those point at files that
        # don't exist, so regenerate them. Plain `openssl req -batch` instead of
        # `prosodyctl cert generate` — prosodyctl prompts on stdin (even with
        # output redirected) and hangs forever in a non-interactive SSH exec.
        # Best-effort (timeout + || true) so a cert quirk doesn't abort the whole
        # deploy — the web UI TLS is served by cloudmodel's own nginx cert
        # regardless; these certs only cover prosody's internal XMPP TLS.
        def regenerate_prosody_certs new
          chroot! @guest.deploy_path, <<~SH, "Failed to regenerate prosody certs"
            mkdir -p /etc/prosody/certs /usr/local/share/ca-certificates
            for host in #{new} auth.#{new}; do
              timeout 60 openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
                -batch -subj "/CN=$host" \
                -keyout "/etc/prosody/certs/$host.key" \
                -out "/etc/prosody/certs/$host.crt" </dev/null >/dev/null 2>&1 || true
              # Trust the new cert system-wide AND in the Java truststore (the
              # ca-certificates-java hook syncs it): jicofo/jvb connect to
              # prosody over TLS and reject an untrusted cert — the package did
              # this for its build-time cert, which the re-point replaced.
              cp "/etc/prosody/certs/$host.crt" "/usr/local/share/ca-certificates/prosody-$host.crt" 2>/dev/null || true
            done
            timeout 120 update-ca-certificates </dev/null >/dev/null 2>&1 || true
            chown -R prosody:prosody /var/lib/prosody /etc/prosody/certs 2>/dev/null || true
          SH
        end

        # Rewrites a `KEY: 'value'` entry in interface_config.js in place.
        def set_interface_value key, value
          # JS string: escape quotes. sed replacement: `&` (whole match),
          # `|` (our delimiter) and `\` are special; newlines end the s///.
          esc = value.to_s.gsub(/[\r\n]/, ' ').gsub("'", "\\\\'").gsub(/[&|\\]/) { "\\#{$&}" }
          chroot! @guest.deploy_path,
            "sed -i \"s|^\\s*#{key}:.*|    #{key}: '#{esc}',|\" #{INTERFACE_CONFIG}",
            "Failed to set jitsi interface value #{key}"
        end
      end
    end
  end
end
