# Per-location nginx configuration overrides embedded in a {CloudModel::Services::Nginx} service.
#
# Allows individual nginx `location` blocks to receive arbitrary directive
# overrides without modifying the service-level template. Each record targets
# one location path and stores a free-form hash of directive key/value pairs
# that are merged into the rendered nginx config for that location.
class CloudModel::Services::Nginx::LocationOverwrite
  include Mongoid::Document
  include Mongoid::Timestamps

  # @!attribute [rw] location
  #   @return [String] nginx location path this record applies to (e.g. `"/api"`)
  field :location, type: String

  # @!attribute [rw] overwrites
  #   @return [Hash] nginx directives to inject into the location block,
  #     e.g. `{ "proxy_read_timeout" => "300" }`
  field :overwrites, type: Hash, default: {}

  validates :location, presence: true, uniqueness: true

  embedded_in :service, class_name: "::CloudModel::Services::Nginx"
end