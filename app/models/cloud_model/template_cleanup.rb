require 'shellwords'

module CloudModel
  # Removes obsolete template tarballs (legacy), ZFS build datasets, and stale
  # build directories — the only things that ever prune /cloud, where template
  # generations otherwise accumulate forever (tens of GB per host).
  #
  # Cleans both sides: the admin's data directory (the canonical copies that
  # sync_inst_images rsyncs to hosts — deleting only host-side would get
  # re-uploaded) and every running host's /cloud.
  #
  # Kept are, per type and architecture:
  # - the newest `keep_per_type` finished templates (what last_useable picks,
  #   plus rollback headroom),
  # - every guest template still referenced by a deployed LXD container
  #   (needed to re-import the container's image), and their core templates.
  #
  # Everything else in a terminal build state (finished/failed/not_started) is
  # deleted: files on admin and hosts, then the template document itself.
  # Build directories are removed for any template not currently building.
  #
  # Driven by `rake cloudmodel:cleanup:templates` (dry run unless CONFIRM=1).
  class TemplateCleanup
    # finished, failed, not_started — never mid-build
    TERMINAL_BUILD_STATES = CloudModel::TERMINAL_BUILD_STATE_IDS

    attr_reader :keep_per_type

    def initialize keep_per_type: 2
      @keep_per_type = [keep_per_type.to_i, 1].max
    end

    # GuestTemplates to keep: all referenced by deployed containers, plus the
    # newest finished ones per type + arch.
    def keep_guest_template_ids
      @keep_guest_template_ids ||= begin
        # LxdContainers are embedded in guests, so collect their template
        # references through the guests collection.
        ids = CloudModel::Guest.collection.distinct('lxd_containers.guest_template_id').compact

        CloudModel::GuestTemplateType.all.each do |type|
          type.templates.where(build_state_id: 0xf0).distinct(:arch).each do |arch|
            ids += type.templates.where(build_state_id: 0xf0, arch: arch)
                       .desc(:_id).limit(keep_per_type).map(&:id)
          end
        end

        ids.uniq
      end
    end

    # Core templates to keep: those the kept guest templates were built from,
    # plus the newest finished ones per arch.
    def keep_core_template_ids
      @keep_core_template_ids ||= begin
        ids = CloudModel::GuestTemplate.where(:id.in => keep_guest_template_ids)
                  .distinct(:core_template_id).compact

        CloudModel::GuestCoreTemplate.where(build_state_id: 0xf0).distinct(:arch).each do |arch|
          ids += CloudModel::GuestCoreTemplate.where(build_state_id: 0xf0, arch: arch)
                     .desc(:_id).limit(keep_per_type).map(&:id)
        end

        ids.uniq
      end
    end

    # Host templates to keep: the newest finished ones per arch (hosts store no
    # template reference — deploys always pick the newest finished).
    def keep_host_template_ids
      @keep_host_template_ids ||= begin
        ids = []
        CloudModel::HostTemplate.where(build_state_id: 0xf0).distinct(:arch).each do |arch|
          ids += CloudModel::HostTemplate.where(build_state_id: 0xf0, arch: arch)
                     .desc(:_id).limit(keep_per_type).map(&:id)
        end
        ids.uniq
      end
    end

    def obsolete_guest_templates
      CloudModel::GuestTemplate.where(:build_state_id.in => TERMINAL_BUILD_STATES,
                                      :id.nin => keep_guest_template_ids)
    end

    def obsolete_core_templates
      CloudModel::GuestCoreTemplate.where(:build_state_id.in => TERMINAL_BUILD_STATES,
                                          :id.nin => keep_core_template_ids)
    end

    def obsolete_host_templates
      CloudModel::HostTemplate.where(:build_state_id.in => TERMINAL_BUILD_STATES,
                                     :id.nin => keep_host_template_ids)
    end

    # All tarball paths (as used on hosts and, prefixed with the data
    # directory, on the admin) belonging to obsolete templates.
    def obsolete_files
      files = []
      obsolete_guest_templates.each do |t|
        files << t.tarball << t.lxd_image_metadata_tarball
      end
      obsolete_core_templates.each { |t| files << t.tarball }
      obsolete_host_templates.each { |t| files << t.tarball }
      files.map(&:to_s)
    end

    # Build datasets of obsolete templates (guest + core; host templates are
    # not built in datasets). Destroy may legitimately fail on a host while an
    # old container still clones the dataset — it is retried on the next run.
    def obsolete_datasets
      @obsolete_datasets ||= obsolete_guest_templates.map(&:build_dataset) +
        obsolete_core_templates.map(&:build_dataset)
    end

    # Build dirs of templates currently building — must never be removed.
    def busy_build_dirs
      @busy_build_dirs ||= begin
        dirs = []
        CloudModel::HostTemplate.where(:build_state_id.nin => TERMINAL_BUILD_STATES)
          .each { |t| dirs << "/cloud/build/host/#{t.id}" }
        CloudModel::GuestCoreTemplate.where(:build_state_id.nin => TERMINAL_BUILD_STATES)
          .each { |t| dirs << "/cloud/build/core/#{t.id}" }
        CloudModel::GuestTemplate.where(:build_state_id.nin => TERMINAL_BUILD_STATES)
          .each { |t| dirs << "/cloud/build/#{t.template_type_id}/#{t.id}" }
        dirs
      end
    end

    # Remove obsolete template files (admin + all running hosts), stale build
    # dirs, and finally the obsolete template documents. With dry_run (the
    # default) only prints what would happen.
    def cleanup! dry_run: true, output: $stdout
      prefix = dry_run ? '[dry-run] ' : ''
      files = obsolete_files

      output.puts 'Dry run — nothing will be deleted.' if dry_run
      output.puts "Obsolete templates: #{obsolete_guest_templates.count} guest, " \
                  "#{obsolete_core_templates.count} core, #{obsolete_host_templates.count} host " \
                  "(#{files.size} files)"

      # Admin-side canonical copies (else sync_inst_images re-uploads them).
      files.each do |file|
        local = "#{CloudModel.config.data_directory}#{file}"
        next unless File.exist? local
        output.puts "#{prefix}admin: rm #{local}"
        File.delete local unless dry_run
      end

      CloudModel::Host.all.reject { |h| [:booting, :not_started].include? h.deploy_state }.each do |host|
        begin
          cleanup_host host, files, dry_run: dry_run, output: output
        rescue => e
          output.puts "! #{host.name}: #{e.class}: #{e.message}"
        end
      end

      unless dry_run
        obsolete_guest_templates.destroy_all
        obsolete_core_templates.destroy_all
        obsolete_host_templates.destroy_all
      end
    end

    private

    def cleanup_host host, files, dry_run:, output:
      prefix = dry_run ? '[dry-run] ' : ''

      unless files.empty?
        output.puts "#{prefix}#{host.name}: rm #{files.size} template file(s)"
        host.exec! "rm -f #{files.map(&:shellescape) * ' '}", 'Failed to remove obsolete template files' unless dry_run
      end

      obsolete_datasets.each do |dataset|
        # Non-bang exec: the dataset may not exist on this host, or still be
        # cloned by a not-yet-deleted container (ZFS refuses then — intended).
        output.puts "#{prefix}#{host.name}: zfs destroy -r #{dataset}"
        host.exec "zfs destroy -r #{dataset.shellescape}" unless dry_run
      end

      busy = busy_build_dirs
      success, listing = host.exec 'ls -d /cloud/build/*/* 2>/dev/null'
      return unless success

      listing.lines.map(&:strip).reject(&:empty?).each do |dir|
        # Only ever remove exact, plausible build dirs (host|core|<type oid>/
        # <template oid>) — this must never match traversal like `..` — and
        # never one that is busy.
        next unless dir =~ %r{\A/cloud/build/(host|core|[0-9a-f]{24})/[0-9a-f]{24}\z}
        next if busy.include? dir

        output.puts "#{prefix}#{host.name}: rm -rf #{dir}"
        host.exec! "rm -rf #{dir.shellescape}", 'Failed to remove stale build dir' unless dry_run
      end
    end
  end
end
