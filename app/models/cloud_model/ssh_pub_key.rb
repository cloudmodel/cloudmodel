module CloudModel
  # A stored SSH public key that can be assigned to {SshGroup}s.
  #
  # During guest deployment, all keys belonging to the SSH service's configured
  # groups are written to the container's `authorized_keys` file.
  class SshPubKey
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] key
    #   @return [String] the full public key string (e.g. `"ssh-ed25519 AAAA... comment"`)
    field :key, type: String
    validates :key, presence: true, uniqueness: true

    # @!attribute [rw] groups
    #   @return [Array<CloudModel::SshGroup>] groups this key belongs to
    has_and_belongs_to_many :groups, class_name: CloudModel::SshGroup, inverse_of: :pub_keys

    # Guests only get keys written at deploy; push changes right away so a
    # removed key loses its access without waiting for the next redeploy.
    after_save :sync_authorized_keys, if: -> { (previous_changes.keys & %w(key group_ids)).any? }
    after_destroy :sync_authorized_keys

    # Enqueues the authorized_keys sync for every guest using one of the
    # groups this key is (or was) in.
    # @return [Boolean] whether the job could be enqueued
    def sync_authorized_keys
      ids = (Array(group_ids) + Array((previous_changes['group_ids'] || []).first)).uniq.map(&:to_s)
      return true if ids.empty?
      CloudModel::GuestJobs::SyncAuthorizedKeysJob.perform_later ids
      true
    rescue => e
      CloudModel.log_exception e
      false
    end

    # Imports all public key lines from a file (e.g. an `authorized_keys` file),
    # creating one {SshPubKey} record per non-blank line.
    # @param filename [String] path to the file
    # @return [void]
    def self.from_file(filename)
      File.readlines(filename).each do |line|
        CloudModel::SshPubKey.create! key: line.strip
      end
    end

    # Returns the comment/label portion of the public key (the last space-separated token).
    # @return [String]
    def name
      key.split(' ').last
    end
  end
end