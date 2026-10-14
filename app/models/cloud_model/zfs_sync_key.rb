require 'shellwords'

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
  # The pair is generated on the controller on first use ({.ensure!}) and
  # distributed by {Workers::HostWorker#deploy_zfs_sync_key}
  # (`rake cloudmodel:host:deploy_zfs_sync_key`, also part of a host deploy).
  module ZfsSyncKey
    extend CloudModel::Mixins::LocalExec

    # Where the private key lives on a host.
    REMOTE_KEY_PATH = '/root/.ssh/zfs_sync'.freeze
    # Forced command bound to the key in authorized_keys.
    WRAPPER_PATH = '/usr/local/sbin/zfs-receive-only'.freeze
    # Comment on the key; also the marker the authorized_keys update keys on.
    COMMENT = 'cloudmodel-zfs-sync'.freeze

    def self.private_key_file
      CloudModel.config.zfs_sync_key_file
    end

    def self.public_key_file
      "#{private_key_file}.pub"
    end

    def self.present?
      File.exist?(private_key_file) and File.exist?(public_key_file)
    end

    # Generates the pair unless it exists. ed25519: small, fast, and not
    # tied to any host's own identity.
    def self.ensure!
      return true if present?

      local_exec "mkdir -p #{File.dirname(private_key_file).shellescape}"
      local_exec! "ssh-keygen -q -N '' -t ed25519 -C #{COMMENT.shellescape} -f #{private_key_file.shellescape}",
        'Failed to generate the ZFS sync key pair'
      File.chmod 0600, private_key_file
      true
    end

    def self.public_key
      File.read(public_key_file).strip
    end

    # The authorized_keys entry: forced command, no pty/forwarding/rc.
    def self.authorized_keys_line
      %(restrict,command="#{WRAPPER_PATH}" #{public_key})
    end
  end
end
