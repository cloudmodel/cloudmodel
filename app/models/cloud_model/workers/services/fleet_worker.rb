module CloudModel
  module Workers
    module Services
      # Worker that configures the Fleet service inside a guest container.
      #
      # Generates the missing secrets and saves them back to the model,
      # renders `/etc/fleet/fleet.yml` and the provisioning scripts:
      # - `fleet.service` gets a drop-in whose root `ExecStartPre` creates
      #   Fleet's database and user in the guest's Percona Server and runs
      #   `fleet prepare db` (migrations, also after a release bump),
      # - `fleet_provision.service` (oneshot, every boot) waits for Fleet,
      #   creates the first administrator and the API-only provisioning user
      #   once, then converges enroll secret and settings with `fleetctl apply`.
      class FleetWorker < CloudModel::Workers::Services::BaseWorker
        def write_config
          comment_sub_step "Config fleet #{@model.effective_fleet_version} (usage statistics #{@model.telemetry ? 'on' : 'off'})"

          # Never render a secret the database does not hold: the next deploy
          # would generate another one and lock the administrator out.
          if @model.generate_secrets
            @model.save or raise "Could not store the generated Fleet secrets: #{@model.errors.full_messages.join(', ')}"
          end

          render_to_guest "/cloud_model/guest/etc/fleet/fleet.yml", "/etc/fleet/fleet.yml", 0640, guest: @guest, model: @model
          render_to_guest "/cloud_model/guest/etc/fleet/prepare_db.sh", "/etc/fleet/prepare_db.sh", 0700, guest: @guest, model: @model
          render_to_guest "/cloud_model/guest/etc/fleet/provision.sh", "/etc/fleet/provision.sh", 0700, guest: @guest, model: @model
          render_to_guest "/cloud_model/guest/etc/fleet/provision.yml", "/etc/fleet/provision.yml", 0600, guest: @guest, model: @model
          # fleet.yml is read by the service user; scripts and specs carry the
          # passwords and stay root-only.
          chroot! @guest.deploy_path, "chown root:fleet /etc/fleet/fleet.yml && chmod 640 /etc/fleet/fleet.yml && chown root:root /etc/fleet/prepare_db.sh /etc/fleet/provision.sh /etc/fleet/provision.yml", "Failed to set fleet config ownership"

        end

        def auto_start
          mkdir_p overlay_path
          render_to_remote "/cloud_model/guest/etc/systemd/system/fleet.service.d/prepare_db.conf", "#{overlay_path}/prepare_db.conf", 0644

          comment_sub_step "Add fleet provisioning to runlevel default"
          render_to_remote "/cloud_model/guest/etc/systemd/system/fleet_provision.service", "#{@guest.deploy_path.shellescape}/etc/systemd/system/fleet_provision.service", 0644
          @host.exec "ln -sf /etc/systemd/system/fleet_provision.service #{@guest.deploy_path.shellescape}/etc/systemd/system/multi-user.target.wants/"

          super
        end
      end
    end
  end
end
