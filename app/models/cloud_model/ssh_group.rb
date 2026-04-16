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
  end
end