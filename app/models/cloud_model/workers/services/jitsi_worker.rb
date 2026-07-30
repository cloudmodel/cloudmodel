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

          comment_sub_step "Brand jitsi UI"

          if @model.watermark_svg
            upload_to_guest @model.watermark_svg, "#{WEB_ROOT}/images/watermark.svg", "0644"
          end

          set_interface_value "APP_NAME", @model.app_name if @model.app_name.present?
          set_interface_value "PROVIDER_NAME", @model.provider_name if @model.provider_name.present?
          set_interface_value "JITSI_WATERMARK_LINK", @model.watermark_link if @model.watermark_link.present?

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
            # jitsi-meet web config
            [ -f /etc/jitsi/meet/#{old}-config.js ] && mv -f /etc/jitsi/meet/#{old}-config.js /etc/jitsi/meet/#{new}-config.js || true
            # nginx site
            if [ -f /etc/nginx/sites-available/#{old}.conf ]; then
              mv -f /etc/nginx/sites-available/#{old}.conf /etc/nginx/sites-available/#{new}.conf
              rm -f /etc/nginx/sites-enabled/#{old}.conf
              ln -sf ../sites-available/#{new}.conf /etc/nginx/sites-enabled/#{new}.conf
            fi
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
        # don't exist, so regenerate them. Best-effort (|| true) so a packaging
        # quirk in the cert path doesn't abort the whole deploy — the web UI TLS
        # is served by cloudmodel's own nginx cert regardless.
        def regenerate_prosody_certs new
          chroot! @guest.deploy_path, <<~SH, "Failed to regenerate prosody certs"
            for host in #{new} auth.#{new}; do
              prosodyctl cert generate "$host" >/dev/null 2>&1 || true
            done
            chown -R prosody:prosody /var/lib/prosody /etc/prosody/certs 2>/dev/null || true
          SH
        end

        # Rewrites a `KEY: 'value'` entry in interface_config.js in place.
        def set_interface_value key, value
          esc = value.to_s.gsub("'", "\\\\'")
          chroot! @guest.deploy_path,
            "sed -i \"s|^\\s*#{key}:.*|    #{key}: '#{esc}',|\" #{INTERFACE_CONFIG}",
            "Failed to set jitsi interface value #{key}"
        end
      end
    end
  end
end
