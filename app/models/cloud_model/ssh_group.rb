module CloudModel
  class SshGroup
    include Mongoid::Document
    include Mongoid::Timestamps

    field :name, type: String
    field :description, type: String

    validates :name, presence: true, uniqueness: true

    has_and_belongs_to_many :pub_keys, class_name: CloudModel::SshPubKey, inverse_of: :groups
  end
end