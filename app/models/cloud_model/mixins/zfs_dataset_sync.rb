module CloudModel
  module Mixins
    # Copies a built ZFS dataset (its `@ready` snapshot) from one host to
    # another via `zfs send | zfs receive`.
    #
    # Preferred route: directly host → host over the private network, the
    # source authenticating at the target with the restricted sync key
    # ({CloudModel::ZfsSyncKey}; both hosts must have it deployed). Fallback,
    # and the only route before that key is rolled out: the stream piped
    # through the controller machine (source → controller → target), the way
    # the tarball scp sync worked.
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

        if direct_zfs_sync?(source_host, target_host)
          sync_zfs_dataset_direct! source_host, target_host, dataset, snapshot
        else
          sync_zfs_dataset_via_controller! source_host, target_host, dataset, snapshot
        end
        true
      end

      # Both ends carry the sync key: the source can push straight to the target.
      def direct_zfs_sync?(source_host, target_host)
        source_host.zfs_sync_key_deployed? and target_host.zfs_sync_key_deployed?
      end

      private

      def controller_ssh(host)
        "ssh -i #{CloudModel.config.ssh_key_file.shellescape} root@#{host.ssh_address}"
      end

      # The controller only drives: it prepares the parent dataset on the
      # target and tells the source to stream. The stream itself takes one
      # hop, source → target, under the restricted key (which permits exactly
      # this receive into the build tree). No -C: build volumes are already
      # lz4/zstd compressed, and the hop stays on the private network.
      def sync_zfs_dataset_direct!(source_host, target_host, dataset, snapshot)
        parent_dataset = File.dirname dataset
        local_exec! "#{controller_ssh(target_host)} 'zfs list #{parent_dataset} >/dev/null 2>&1 || zfs create -p #{parent_dataset}'",
          "Failed to create parent dataset on #{target_host.name}"

        peer_ssh = "ssh -i #{CloudModel::ZfsSyncKey::REMOTE_KEY_PATH} -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@#{target_host.ssh_address}"
        local_exec! "#{controller_ssh(source_host)} 'zfs send -p #{snapshot} | #{peer_ssh} \"zfs receive -u -F #{dataset}\"'",
          "Failed to sync build volume #{dataset} from #{source_host.name} to #{target_host.name} (direct)"
      end

      # -C: the stream is multi-GB and routed source → controller → target.
      # A build volume may be a ZFS CLONE of a template snapshot. `send -R`
      # would emit an origin-dependent stream that the target can only
      # receive when it already has that origin. A plain send of the snapshot
      # is a full, self-contained stream; -p keeps the dataset properties
      # (com.cloudmodel:status etc.). lz4 is universal, so the carried
      # compression property is accepted on any OpenZFS.
      def sync_zfs_dataset_via_controller!(source_host, target_host, dataset, snapshot)
        ssh_source = "ssh -C -i #{CloudModel.config.ssh_key_file.shellescape} root@#{source_host.ssh_address}"
        ssh_target = "ssh -C -i #{CloudModel.config.ssh_key_file.shellescape} root@#{target_host.ssh_address}"
        parent_dataset = File.dirname dataset

        local_exec! "#{ssh_target} 'zfs list #{parent_dataset} >/dev/null 2>&1 || zfs create -p #{parent_dataset}'",
          "Failed to create parent dataset on #{target_host.name}"
        local_exec! "#{ssh_source} 'zfs send -p #{snapshot}' | #{ssh_target} 'zfs receive -u -F #{dataset}'",
          "Failed to sync build volume #{dataset} from #{source_host.name} to #{target_host.name}"
      end
    end
  end
end
