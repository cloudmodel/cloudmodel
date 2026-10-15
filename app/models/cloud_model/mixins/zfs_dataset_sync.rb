module CloudModel
  module Mixins
    # Copies a built ZFS dataset snapshot from one host to another via
    # `zfs send | zfs receive`.
    #
    # Preferred route: directly host → host over the private network, the
    # source authenticating at the target with the restricted sync key
    # ({CloudModel::ZfsSyncKey}; both hosts must have it deployed — the first
    # sync pushes it). Fallback: the stream piped through the controller
    # machine (source → controller → target), the way the tarball scp sync
    # worked.
    #
    # A dataset that already exists on the target (an earlier version of a
    # web image artifact, with release clones hanging off its snapshots) can
    # not take a full stream again; the new snapshot is sent incrementally
    # from the target's newest snapshot. Only a dataset without any snapshot
    # in common (an aborted or foreign receive) is replaced, and only if
    # nothing depends on it.
    #
    # Shared by {HasZfsBuildVolume} (guest/core templates) and {WebImage}
    # (Rails app volumes), which both build on a per-arch build host and then
    # sync the result to the deploy target.
    module ZfsDatasetSync
      include CloudModel::Mixins::LocalExec

      # Dataset and snapshot names are interpolated into remote shell
      # commands; this is the whole character set they may use.
      ZFS_NAME = /\A[A-Za-z0-9._\/-]+(@[A-Za-z0-9._-]+)?\z/

      # @param source_host [CloudModel::Host] host that has the snapshot
      # @param target_host [CloudModel::Host] host to receive it
      # @param dataset [String] ZFS dataset name the snapshot is received into
      # @param snapshot [String, nil] the snapshot to send (default: the
      #   dataset's `@ready` — web images pass a versioned `@v<ts>` instead)
      # @return [true]
      # @raise [RuntimeError] on a failed send/receive or an unsafe name
      def sync_zfs_dataset!(source_host, target_host, dataset, snapshot: nil)
        snapshot ||= CloudModel::BuildZfsVolume.ready_snapshot dataset
        [dataset, snapshot].each do |name|
          raise "Refusing to sync ZFS dataset with unexpected name #{name.inspect}" unless name =~ ZFS_NAME
        end

        send_args = zfs_send_args source_host, target_host, dataset, snapshot

        if direct_zfs_sync?(source_host, target_host) or provision_zfs_sync_key!(source_host, target_host)
          sync_zfs_dataset_direct! source_host, target_host, dataset, send_args
        else
          sync_zfs_dataset_via_controller! source_host, target_host, dataset, send_args
        end
        destroy_stale_zfs_datasets target_host, dataset
        true
      end

      # Both ends carry the sync key: the source can push straight to the target.
      def direct_zfs_sync?(source_host, target_host)
        source_host.zfs_sync_key_deployed? and target_host.zfs_sync_key_deployed?
      end

      # Pushes the sync key to whichever of the two hosts lacks it, so the
      # first sync between them already goes direct — no separate rollout
      # step. A host that cannot be prepared (unreachable, push failed) is
      # logged and leaves this sync on the controller route.
      # @return [Boolean] true if both hosts now carry the key
      def provision_zfs_sync_key!(source_host, target_host)
        [source_host, target_host].each do |host|
          next if host.zfs_sync_key_deployed?
          begin
            CloudModel::Workers::HostWorker.new(host).deploy_zfs_sync_key
          rescue Exception => e
            Rails.logger.warn "ZfsDatasetSync: could not push the sync key to #{host.name}, syncing via controller: #{e.class}: #{e.message}"
            CloudModel.log_exception e
          end
        end
        direct_zfs_sync? source_host, target_host
      end

      # Snapshots of `dataset` on `host`, oldest first (nil if the dataset
      # does not exist there).
      def zfs_snapshots_on(host, dataset)
        success, list = host.exec "zfs list -H -o name -t snapshot -d 1 -s creation #{dataset}"
        return nil unless success
        list.to_s.split("\n").map(&:strip).reject(&:empty?)
      end

      private

      # Decides between a full and an incremental stream. A full stream can
      # only land where the dataset does not exist. If it exists on the
      # target, the newest snapshot there is the incremental base as long as
      # the source still has it. Otherwise (the source pruned it, or the
      # target holds a leftover) the target's dataset is moved aside under a
      # `-stale-<ts>` name: release clones hanging off its snapshots stay
      # valid (a rename keeps clone origins), the fresh name takes a full
      # stream, and {#destroy_stale_zfs_datasets} removes moved-aside
      # datasets once nothing depends on them any more.
      def zfs_send_args(source_host, target_host, dataset, snapshot)
        target_snaps = zfs_snapshots_on target_host, dataset
        return "-p #{snapshot}" if target_snaps.nil?

        base = target_snaps.last
        if base and (zfs_snapshots_on(source_host, dataset) || []).include?(base)
          "-p -i #{base} #{snapshot}"
        else
          stale = "#{dataset}-stale-#{Time.now.utc.strftime('%Y%m%d%H%M%S')}"
          target_host.exec! "zfs rename #{dataset} #{stale} && zfs set canmount=off #{stale}",
            "#{dataset} on #{target_host.name} has no snapshot in common with #{source_host.name} and could not be moved aside"
          "-p #{snapshot}"
        end
      end

      # Destroys every moved-aside `*-stale-<ts>` dataset next to `dataset`
      # on `host` whose clones are all gone (a destroy with dependents just
      # fails and leaves it for next time). Sweeping the whole parent means a
      # leftover is reclaimed by any later sync into that tree, not only by
      # one of the same dataset.
      def destroy_stale_zfs_datasets(host, dataset)
        success, list = host.exec "zfs list -H -o name -d 1 -t filesystem #{File.dirname dataset}"
        return unless success
        list.to_s.split("\n").map(&:strip).each do |stale|
          next unless stale =~ /-stale-\d+\z/
          host.exec "zfs destroy -r #{stale}"
        end
      end

      def controller_ssh(host)
        "ssh -i #{CloudModel.config.ssh_key_file.shellescape} root@#{host.ssh_address}"
      end

      # The controller only drives: it prepares the parent dataset on the
      # target and tells the source to stream. The stream itself takes one
      # hop, source → target, under the restricted key (which permits exactly
      # this receive into the build tree). The peer is addressed by its
      # private (VPN) address — ssh_address is the controller's own route to
      # the host, which may be the public one. No -C: build volumes are
      # already lz4/zstd compressed, and the hop stays on the private network.
      def sync_zfs_dataset_direct!(source_host, target_host, dataset, send_args)
        parent_dataset = File.dirname dataset
        local_exec! "#{controller_ssh(target_host)} 'zfs list #{parent_dataset} >/dev/null 2>&1 || zfs create -p #{parent_dataset}'",
          "Failed to create parent dataset on #{target_host.name}"

        peer_ssh = "ssh -i #{CloudModel::ZfsSyncKey::REMOTE_KEY_PATH} -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@#{target_host.private_address}"
        local_exec! "#{controller_ssh(source_host)} 'zfs send #{send_args} | #{peer_ssh} \"zfs receive -u -F #{dataset}\"'",
          "Failed to sync build volume #{dataset} from #{source_host.name} to #{target_host.name} (direct)"
      end

      # -C: the stream is multi-GB and routed source → controller → target.
      # A build volume may be a ZFS CLONE of a template snapshot. `send -R`
      # would emit an origin-dependent stream that the target can only
      # receive when it already has that origin. A plain send of the snapshot
      # is a full, self-contained stream; -p keeps the dataset properties
      # (com.cloudmodel:status etc.). lz4 is universal, so the carried
      # compression property is accepted on any OpenZFS.
      def sync_zfs_dataset_via_controller!(source_host, target_host, dataset, send_args)
        ssh_source = "ssh -C -i #{CloudModel.config.ssh_key_file.shellescape} root@#{source_host.ssh_address}"
        ssh_target = "ssh -C -i #{CloudModel.config.ssh_key_file.shellescape} root@#{target_host.ssh_address}"
        parent_dataset = File.dirname dataset

        local_exec! "#{ssh_target} 'zfs list #{parent_dataset} >/dev/null 2>&1 || zfs create -p #{parent_dataset}'",
          "Failed to create parent dataset on #{target_host.name}"
        local_exec! "#{ssh_source} 'zfs send #{send_args}' | #{ssh_target} 'zfs receive -u -F #{dataset}'",
          "Failed to sync build volume #{dataset} from #{source_host.name} to #{target_host.name}"
      end
    end
  end
end
