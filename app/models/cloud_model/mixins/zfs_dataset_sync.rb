module CloudModel
  module Mixins
    # Copies a built ZFS dataset (its `@ready` snapshot) from one host to
    # another via `zfs send | zfs receive`, piped through the admin machine
    # (hosts don't SSH to each other — same route the tarball scp sync took).
    #
    # Shared by {HasZfsBuildVolume} (guest/core templates) and {WebImage}
    # (Rails app volumes), which both build on a per-arch build host and then
    # sync the result to the deploy target.
    module ZfsDatasetSync
      include CloudModel::Mixins::LocalExec

      # @param source_host [CloudModel::Host] host that has the snapshot
      # @param target_host [CloudModel::Host] host to receive it
      # @param dataset [String] ZFS dataset name the snapshot is received into
      # @param snapshot [String, nil] the snapshot to send (default: the
      #   dataset's `@ready` — web images pass a versioned `@v<ts>` instead)
      # @return [true]
      # @raise [RuntimeError] on a failed send/receive
      def sync_zfs_dataset!(source_host, target_host, dataset, snapshot: nil)
        # -C: the stream is multi-GB and routed source → admin → target
        ssh_source = "ssh -C -i #{CloudModel.config.ssh_key_file.shellescape} root@#{source_host.ssh_address}"
        ssh_target = "ssh -C -i #{CloudModel.config.ssh_key_file.shellescape} root@#{target_host.ssh_address}"
        snapshot ||= CloudModel::BuildZfsVolume.ready_snapshot dataset
        parent_dataset = File.dirname dataset

        local_exec! "#{ssh_target} 'zfs list #{parent_dataset.shellescape} >/dev/null 2>&1 || zfs create -p #{parent_dataset.shellescape}'",
          "Failed to create parent dataset on #{target_host.name}"
        # A build volume may be a ZFS CLONE of a template snapshot. `send -R`
        # would emit an origin-dependent stream that the target can only
        # receive when it already has that origin. A plain send of the @ready
        # snapshot is a full, self-contained stream; -p keeps the dataset
        # properties (com.cloudmodel:status etc.). lz4 is universal, so the
        # carried compression property is accepted on any OpenZFS.
        local_exec! "#{ssh_source} 'zfs send -p #{snapshot.shellescape}' | #{ssh_target} 'zfs receive -u -F #{dataset.shellescape}'",
          "Failed to sync build volume #{dataset} from #{source_host.name} to #{target_host.name}"

        true
      end
    end
  end
end
