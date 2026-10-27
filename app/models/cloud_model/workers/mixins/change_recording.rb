module CloudModel
  module Workers
    module Mixins
      # Collects the evidence of a guest deploy and publishes it as the
      # ActiveSupport notification `guest_deploy.cloud_model`: the container
      # and template before and after, the package diff between the old and
      # the new container, the web images of the nginx services and a smoke
      # test right after the start. cloudmodel stores nothing itself; the
      # application subscribes and writes the evidence wherever its change or
      # audit trail lives:
      #
      #   ActiveSupport::Notifications.subscribe('guest_deploy.cloud_model') do |*, payload|
      #     # payload[:state] is 'succeeded', 'degraded', 'prepared' or 'failed'
      #   end
      #
      # Every method swallows its own errors: missing evidence is logged, but
      # it never fails or blocks the deploy it describes.
      module ChangeRecording
        EVENT = 'guest_deploy.cloud_model'.freeze
        PACKAGE_QUERY = "dpkg-query -W -f='${Package}\\t${Version}\\n'".freeze

        # Parses `dpkg-query -W -f='${Package}\t${Version}\n'` output.
        # @return [Hash{String=>String}] package => version
        def self.parse_packages output
          output.to_s.each_line.each_with_object({}) do |line, packages|
            name, version = line.chomp.split("\t", 2)
            packages[name] = version.to_s if name.present?
          end
        end

        # Package diff between two package lists; nil when either is missing.
        # @return [Hash, nil] {added: [[pkg, ver]], removed: [[pkg, ver]],
        #   changed: [[pkg, old, new]]}
        def self.package_diff before, after
          return nil if before.blank? or after.blank?
          {
            added: (after.keys - before.keys).sort.map { |p| [p, after[p]] },
            removed: (before.keys - after.keys).sort.map { |p| [p, before[p]] },
            changed: (before.keys & after.keys).sort.select { |p| before[p] != after[p] }.map { |p| [p, before[p], after[p]] }
          }
        end

        # @param template [CloudModel::GuestTemplate, nil]
        # @return [Hash, nil]
        def self.template_info template
          return nil unless template
          {id: template.id.to_s, name: template.name.to_s, built_at: template.created_at}
        end

        # Starts collecting before anything is built: the running container,
        # its template and package list, the web images to be deployed.
        # @param kind [String] 'deploy' or 'switch'
        def begin_change_record kind = 'deploy'
          current = guest.current_lxd_container
          @change_event = {
            guest_id: guest.id.to_s, guest_name: guest.name, host_name: host.name, kind: kind,
            started_at: Time.now,
            container_before: current&.name,
            template_before: ChangeRecording.template_info(current&.guest_template),
            web_images: change_web_images
          }
          @change_packages_before = current ? running_packages : nil
        rescue Exception => e
          CloudModel.log_exception e
          @change_event = nil
        end

        # Reads the package list of the new container from its mounted
        # rootfs, after all configuration (and the security updates of
        # refresh_unattended_upgrades) is in place.
        def record_new_container
          return unless @change_event
          _, output = host.exec "chroot #{guest.deploy_path.shellescape} #{PACKAGE_QUERY}"
          after = ChangeRecording.parse_packages(output)
          @change_event[:package_count] = after.size if after.present?
          @change_event[:packages] = ChangeRecording.package_diff(@change_packages_before, after)
          @change_event[:container_after] = @lxc&.name
          @change_event[:template_after] = ChangeRecording.template_info(@lxc&.guest_template || @template)
        rescue Exception => e
          CloudModel.log_exception e
        end

        # A deploy that stops before the switch-over (launch: false): the
        # package diff is published now, the smoke test with the switch.
        def prepare_change_record
          publish_change_record state: 'prepared'
        end

        # Starts the record of a deferred switch-over to a prepared container.
        def resume_change_record
          begin_change_record 'switch'
          @change_event[:container_after] = @lxc&.name if @change_event
        end

        # Runs the smoke test on the started guest and publishes the record.
        def finish_change_record
          return unless @change_event
          checks = change_smoke_checks
          @change_event[:container_after] = guest.current_lxd_container&.name || @change_event[:container_after]
          publish_change_record state: (checks.all? { |c| c[:ok] } ? 'succeeded' : 'degraded'), checks: checks
        rescue Exception => e
          CloudModel.log_exception e
        end

        # @param error [Exception]
        def fail_change_record error
          publish_change_record state: 'failed', error: error.message.to_s[0, 2000]
        end

        private

        def publish_change_record **fields
          return unless @change_event
          payload = @change_event.merge(fields).merge(finished_at: Time.now)
          ActiveSupport::Notifications.instrument EVENT, payload
          @change_event = nil
        rescue Exception => e
          CloudModel.log_exception e
        end

        # Package list of the running container.
        # @return [Hash{String=>String}, nil]
        def running_packages
          success, output = guest.exec "sh -c #{PACKAGE_QUERY.shellescape}"
          success ? ChangeRecording.parse_packages(output) : nil
        rescue Exception => e
          CloudModel.log_exception e
          nil
        end

        # @return [Array<Hash>]
        def change_web_images
          guest.services.select { |s| s.respond_to?(:deploy_web_image_id) and s.deploy_web_image_id.present? }.map do |service|
            image = service.deploy_web_image
            {service: service.name.to_s, image: image&.name, branch: image&.git_branch, commit: image&.git_commit}
          end
        end

        # Smoke test right after the start: systemd reaches a running state
        # (waits up to two minutes) and no unit failed.
        # @return [Array<Hash>] {name:, ok:, detail:}
        def change_smoke_checks
          _, state = guest.exec "sh -c #{'timeout 120 systemctl is-system-running --wait 2>/dev/null || systemctl is-system-running'.shellescape}"
          state = state.to_s.strip.lines.last.to_s.strip
          _, failed = guest.exec "systemctl --failed --no-legend --plain"
          units = failed.to_s.lines.map { |line| line.split.first }.compact.reject { |u| u.start_with?('●') }
          [
            {name: 'systemd running', ok: state == 'running', detail: state},
            {name: 'no failed units', ok: units.empty?, detail: units * ', '}
          ]
        end
      end
    end
  end
end
