require 'shellwords'

module CloudModel
  # One-time migration of tarball-built templates into ZFS build volumes.
  #
  # Deploys clone containers from a template's ZFS volume — templates built
  # before the ZFS workflow only exist as tarballs (on hosts under
  # /cloud/templates and on the admin machine in the data directory). Some of
  # them can no longer be rebuilt (dead package sources, retired OS versions),
  # so this migration unpacks the existing artifacts into build volumes on the
  # build host instead: tarball → rootfs/, LXD metadata beside it, identity
  # scrub (ssh host keys, machine-id), ready snapshot.
  #
  # Migrated are the templates worth keeping (same keep sets as
  # {TemplateCleanup}): everything referenced by deployed containers plus the
  # newest finished generation per type/arch, and their core templates.
  #
  # Driven by `rake cloudmodel:migrate:templates_to_zfs` (dry run unless
  # CONFIRM=1).
  class ZfsTemplateMigration
    include CloudModel::Mixins::LocalExec

    attr_reader :host

    def initialize host
      @host = host
    end

    # Templates to migrate, cores first (guest template volumes don't depend
    # on them, but a complete set allows future component rebuilds).
    def templates
      keep = CloudModel::TemplateCleanup.new
      CloudModel::GuestCoreTemplate.where(:id.in => keep.keep_core_template_ids, build_state_id: 0xf0).to_a +
        CloudModel::GuestTemplate.where(:id.in => keep.keep_guest_template_ids, build_state_id: 0xf0).to_a
    end

    def migrate! dry_run: true, output: $stdout
      output.puts 'Dry run — nothing will be migrated. Run with CONFIRM=1 to apply.' if dry_run

      results = {migrated: 0, present: 0, missing: 0, failed: 0}
      templates.each do |template|
        results[migrate_template(template, dry_run: dry_run, output: output)] += 1
      end

      output.puts "Done: #{results[:migrated]} migrated, #{results[:present]} already present, " \
                  "#{results[:missing]} without tarball, #{results[:failed]} failed."
      results
    end

    def migrate_template template, dry_run: true, output: $stdout
      output.print "#{template.class.model_name.element} #{template.id} (#{template.name}): "

      volume = template.build_volume host
      if volume.ready?
        output.puts 'already migrated'
        return :present
      end

      source = tarball_source template.tarball
      unless source
        output.puts "NO TARBALL FOUND — cannot migrate (and may not be rebuildable); " \
                    "place #{template.tarball} on #{host.name} or the admin machine and rerun"
        return :missing
      end

      if dry_run
        output.puts "[dry-run] would migrate from #{describe_source source}"
        return :migrated
      end

      stage_tarball template.tarball, source
      unpack_template template, volume
      # Same identity scrub new builds get — the old tarballs already
      # excluded ssh host keys, but carried a machine-id.
      volume.scrub_identity!
      volume.commit!
      volume.unmount!
      template.update_attributes build_host: host

      output.puts "migrated from #{describe_source source}"
      :migrated
    rescue Exception => e
      CloudModel.log_exception e
      output.puts "FAILED (#{e.class}: #{e.message})"
      :failed
    end

    # Finds a copy of the tarball: on the target host, on the admin machine
    # (where download_template archived every build), or on another host.
    # @return [Array, nil] [:host] | [:admin, path] | [:remote_host, host] | nil
    def tarball_source tarball
      return [:host] if file_on_host? host, tarball

      admin_path = "#{CloudModel.config.data_directory}#{tarball}"
      return [:admin, admin_path] if File.exist? admin_path

      other = CloudModel::Host.where(:id.ne => host.id).to_a.find do |h|
        begin
          file_on_host? h, tarball
        rescue Exception => e
          CloudModel.log_exception e
          false
        end
      end
      return [:remote_host, other] if other

      nil
    end

    private

    def describe_source source
      case source[0]
      when :host then "tarball on #{host.name}"
      when :admin then "admin machine (#{source[1]})"
      when :remote_host then "host #{source[1].name}"
      end
    end

    def file_on_host? a_host, path
      a_host.sftp.stat! path
      true
    rescue Exception
      false
    end

    # Makes sure the tarball is on the target host, copying it from the admin
    # machine or piping it from another host (via the admin machine — hosts
    # don't SSH to each other).
    def stage_tarball tarball, source
      return if source[0] == :host

      host.exec! "mkdir -p #{File.dirname(tarball).shellescape}", 'Failed to create template directory'
      key_file = CloudModel.config.ssh_key_file
      case source[0]
      when :admin
        local_exec! "scp -C -i #{key_file.shellescape} #{source[1].shellescape} root@#{host.ssh_address}:#{tarball.shellescape}",
          'Failed to upload template tarball'
      when :remote_host
        local_exec! "ssh -C -i #{key_file.shellescape} root@#{source[1].ssh_address} 'cat #{tarball.shellescape}' | " \
                    "ssh -C -i #{key_file.shellescape} root@#{host.ssh_address} 'cat > #{tarball.shellescape}'",
          "Failed to pipe template tarball from #{source[1].name}"
      end
    end

    def unpack_template template, volume
      volume.prepare!
      host.exec! "mkdir -p #{volume.rootfs_path.shellescape}", 'Failed to create rootfs directory'
      host.exec! "cd #{volume.rootfs_path.shellescape} && tar xzpf #{template.tarball.shellescape}", 'Failed to unpack template tarball'

      # Guest templates also carry an LXD metadata tarball (metadata.yaml +
      # templates/) unpacked beside the rootfs; optional — deploys work
      # without it.
      if template.respond_to?(:lxd_image_metadata_tarball) and file_on_host?(host, template.lxd_image_metadata_tarball)
        host.exec! "cd #{volume.mountpoint.shellescape} && tar xzf #{template.lxd_image_metadata_tarball.shellescape}", 'Failed to unpack template metadata'
      end
    end

  end
end
