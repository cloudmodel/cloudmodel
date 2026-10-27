module CloudModel
  # A named group of {SshPubKey} records.
  #
  # Groups are referenced by SSH service configurations to control which public
  # keys are written to `authorized_keys` files on guests.
  class SshGroup
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [rw] name
    #   @return [String] unique group name
    field :name, type: String

    # @!attribute [rw] description
    #   @return [String, nil] optional human-readable description of the group's purpose
    field :description, type: String

    validates :name, presence: true, uniqueness: true

    # @!attribute [rw] pub_keys
    #   @return [Array<CloudModel::SshPubKey>] keys that belong to this group
    has_and_belongs_to_many :pub_keys, class_name: CloudModel::SshPubKey, inverse_of: :groups

    # A key added to or removed from the group must reach the guests using
    # it without a redeploy (see {CloudModel::GuestJobs::SyncAuthorizedKeysJob}).
    after_save :sync_authorized_keys, if: -> { previous_changes.key? 'pub_key_ids' }

    # Enqueues the authorized_keys sync for every guest using this group.
    # @return [Boolean] whether the job could be enqueued
    def sync_authorized_keys
      CloudModel::GuestJobs::SyncAuthorizedKeysJob.perform_later [id.to_s]
      true
    rescue => e
      CloudModel.log_exception e
      false
    end
  end
end