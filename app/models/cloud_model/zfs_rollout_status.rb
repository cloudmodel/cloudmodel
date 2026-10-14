module CloudModel
  # Read-only overview of the move from image/tarball deploys to ZFS volumes.
  #
  # Three things decide whether a guest can be served by the current deploy
  # code without surprises, and this report lists all of them per host:
  #
  # * **Container layout** — guests whose live container was created from an
  #   LXD image (the retired path) can not receive web image rollouts; one full
  #   guest redeploy moves them to the template volume layout. Containers that
  #   predate the recorded origin are probed on the host (ZFS `origin`), and
  #   the answer is persisted so later checks need no host access.
  # * **Templates** — a redeploy clones the newest finished template of the
  #   guest's type from a build volume on the guest's host. Missing volumes are
  #   synced or rebuilt on demand, which is slow and, for templates that can no
  #   longer be rebuilt, impossible without `rake cloudmodel:migrate:templates_to_zfs`.
  #   Types without any finished template build one synchronously on the
  #   guest's own host during the redeploy.
  # * **Web images** — a rollout clones the image's built artifact for the
  #   guest's arch; images without one are built on first use.
  #
  # Nothing here builds, deploys or deletes anything. Driven by
  # `rake cloudmodel:zfs:status` (PROBE=0 skips host access).
  class ZfsRolloutStatus
    attr_reader :hosts, :probe

    # @param hosts [Array<CloudModel::Host>] hosts to report on
    # @param probe [Boolean] ask hosts for unknown container layouts and for
    #   template volume presence; false reports only what the database knows
    def initialize hosts: nil, probe: true
      @hosts = hosts || CloudModel::Host.all.to_a.sort_by(&:name)
      @probe = probe
    end

    # One row per guest: container layout and web image rollout state.
    def guest_rows
      hosts.flat_map do |host|
        host.guests.to_a.sort_by(&:name).map do |guest|
          nginx = guest.services.detect { |s| s.is_a? CloudModel::Services::Nginx }
          {
            host: host,
            guest: guest,
            origin: guest.rootfs_origin(detect: probe),
            web_image: nginx&.deploy_web_image,
            rollout_state: nginx&.redeploy_web_image_state
          }
        end
      end
    end

    # One row per (host, template) a redeploy on that host would clone from.
    # Resolves templates read-only — unlike Guest#template, which builds a
    # missing one on the spot.
    def template_rows
      hosts.flat_map do |host|
        by_template = Hash.new { |h, k| h[k] = [] }
        untyped = []

        unresolvable = []

        host.guests.to_a.sort_by(&:name).each do |guest|
          template = begin
            next_template_for guest
          rescue => e
            # e.g. a service referencing a web app class that no longer exists:
            # that guest can not be redeployed as stored, which is exactly
            # what the report is for — note it instead of aborting the run.
            unresolvable << {guest: guest, error: "#{e.class}: #{e.message}"}
            next
          end

          if template
            by_template[template] << guest
          else
            untyped << guest
          end
        end

        rows = by_template.map do |template, guests|
          {host: host, template: template, guests: guests, volume_ready: template_volume_ready?(template, host)}
        end
        rows << {host: host, template: nil, guests: untyped, volume_ready: false} if untyped.any?
        unresolvable.each do |entry|
          rows << {host: host, template: nil, guests: [entry[:guest]], volume_ready: false, error: entry[:error]}
        end
        rows
      end
    end

    # One row per web image and arch it must exist for.
    def web_image_rows
      CloudModel::WebImage.all.to_a.sort_by(&:name).flat_map do |image|
        arches = begin
          image.build_targets
        rescue => e
          next [{image: image, arch: nil, version: nil, error: e.message}]
        end

        next [{image: image, arch: nil, version: nil, error: 'not used by any deployed guest'}] if arches.empty?

        arches.map { |arch| {image: image, arch: arch, version: image.artifact_version(arch), error: nil} }
      end
    end

    def legacy_guests
      guest_rows.select { |row| row[:origin] == CloudModel::LxdContainer::ROOTFS_IMAGE }
    end

    def report output: $stdout
      output.puts "Hosts: #{hosts.map(&:name) * ', '}" if hosts.any?
      output.puts '(database only — PROBE=1 asks the hosts)' unless probe
      output.puts

      guests = guest_rows
      output.puts "== Guests (container layout) =="
      guests.each do |row|
        layout = case row[:origin]
        when CloudModel::LxdContainer::ROOTFS_TEMPLATE_VOLUME then 'template volume'
        when CloudModel::LxdContainer::ROOTFS_IMAGE then 'IMAGE (legacy) — one full guest redeploy required'
        else row[:guest].current_lxd_container ? 'unknown' : 'no container'
        end
        rollout = row[:web_image] ? " | web image #{row[:web_image].name}: #{row[:rollout_state]}" : ''
        output.puts "  #{row[:host].name}/#{row[:guest].name}: #{layout}#{rollout}"
      end
      output.puts

      output.puts "== Templates a redeploy would clone (per host) =="
      template_rows.each do |row|
        names = row[:guests].map(&:name) * ', '
        if row[:error]
          output.puts "  #{row[:host].name}: #{names}: CAN NOT resolve template — #{row[:error]}"
        elsif row[:template].nil?
          output.puts "  #{row[:host].name}: NO finished template for #{names} — the redeploy builds one on this host first"
        else
          state = if !probe then 'not probed'
          elsif row[:volume_ready] then 'volume ready'
          else 'volume MISSING on host — synced or rebuilt on first redeploy (migrate:templates_to_zfs / host:prepare_zfs_templates)'
          end
          output.puts "  #{row[:host].name}: #{row[:template].name}: #{state} (#{names})"
        end
      end
      output.puts

      output.puts "== Web images =="
      web_image_rows.each do |row|
        if row[:error]
          output.puts "  #{row[:image].name}: #{row[:error]}"
        elsif row[:version]
          output.puts "  #{row[:image].name} (#{row[:arch]}): artifact v#{row[:version]}"
        else
          output.puts "  #{row[:image].name} (#{row[:arch]}): NO artifact — built on the first rollout or guest redeploy"
        end
      end
      output.puts

      legacy = guests.count { |row| row[:origin] == CloudModel::LxdContainer::ROOTFS_IMAGE }
      unknown = guests.count { |row| row[:origin].nil? && row[:guest].current_lxd_container }
      output.puts "Summary: #{guests.size} guests, #{legacy} on the legacy image layout, #{unknown} unknown."
      output.puts "Legacy guests keep running; web image rollouts to them are refused until their one-time guest redeploy." if legacy > 0
    end

    private

    # The template a redeploy on the guest's host would pick: newest finished
    # one of the guest's type and arch, or nil (the deploy builds one then).
    def next_template_for guest
      return nil unless guest.host

      type_ids = CloudModel::GuestTemplateType.where(components: guest.components_needed, os_version: guest.os_version).pluck(:id)
      return nil if type_ids.empty?

      CloudModel::GuestTemplate.where(:template_type_id.in => type_ids, arch: guest.host.arch, build_state_id: 0xf0).last
    end

    def template_volume_ready? template, host
      return false unless probe
      template.build_volume(host).ready?
    rescue => e
      Rails.logger.warn "ZfsRolloutStatus: could not check #{template.name} on #{host.name}: #{e.message}"
      false
    end
  end
end
