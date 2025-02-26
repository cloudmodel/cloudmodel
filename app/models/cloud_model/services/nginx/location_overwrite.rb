class CloudModel::Services::Nginx::LocationOverwrite
  include Mongoid::Document
  include Mongoid::Timestamps

  field :location, type: String
  field :overwrites, type: Hash, default: {}

  validates :location, presence: true, uniqueness: true

  embedded_in :service, class_name: "::CloudModel::Services::Nginx"
end