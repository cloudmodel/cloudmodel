module CloudModel
  # The key pair hosts use among themselves to stream build volumes directly
  # (`zfs send | zfs receive` host → host) instead of piping multi-GB streams
  # through the controller machine.
  #
  # Trust is deliberately narrow: the public key lands in every host's
  # `/root/.ssh/authorized_keys` with `restrict` and a forced command
  # ({WRAPPER_PATH}) that only permits receiving into the build dataset tree
  # (plus the `zfs create -p` / `zfs list` of the parent that a receive needs).
  # So a host holding the private key can push build volumes to its peers and
  # nothing else — no shell, no forwarding, no other datasets.
  #
  # Nothing has to be prepared by hand: the pair is generated on the
  # controller when first needed ({.ensure!}), and the first sync between two
  # hosts pushes it to them ({Workers::HostWorker#deploy_zfs_sync_key}, see
  # {Mixins::ZfsDatasetSync}). `rake cloudmodel:host:deploy_zfs_sync_key`
  # rolls it out ahead of time; a host deploy installs it as well.
  module ZfsSyncKey
    # Where the private key lives on a host.
    REMOTE_KEY_PATH = '/root/.ssh/zfs_sync'.freeze
    # Forced command bound to the key in authorized_keys.
    WRAPPER_PATH = '/usr/local/sbin/zfs-receive-only'.freeze
    # Comment on the key; also the marker the authorized_keys update keys on.
    COMMENT = 'cloudmodel-zfs-sync'.freeze

    # ed25519: small, fast, and not tied to any host's own identity.
    def self.pair
      CloudModel::SshKeyPair.new CloudModel.config.zfs_sync_key_file, type: 'ed25519', comment: COMMENT
    end

    def self.private_key_file
      pair.private_key_file
    end

    def self.public_key_file
      pair.public_key_file
    end

    def self.present?
      pair.present?
    end

    # Generates the pair unless it exists.
    def self.ensure!
      pair.ensure!
    end

    def self.public_key
      pair.public_key
    end

    # The authorized_keys entry: forced command, no pty/forwarding/rc.
    def self.authorized_keys_line
      %(restrict,command="#{WRAPPER_PATH}" #{public_key})
    end
  end
end
