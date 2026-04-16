module CloudModel
  # Represents an additional ZFS pool embedded in a {Host}.
  #
  # The host's primary pool is created automatically during deployment.
  # Extra ZPools can be defined here and are initialised via their
  # {#init_string} (passed directly to `zpool create`).
  class Zpool
    include Mongoid::Document
    include Mongoid::Timestamps

    # @!attribute [rw] host
    #   @return [CloudModel::Host] the host this pool belongs to (polymorphic)
    embedded_in :host, :polymorphic => true

    # @!attribute [rw] name
    #   @return [String] ZFS pool name (must be unique)
    field :name, type: String

    # @!attribute [rw] init_string
    #   @return [String] arguments passed to `zpool create` when initialising the pool
    #     (e.g. `"mirror sda sdb"`)
    field :init_string, type: String

    validates :name, presence: true, uniqueness: true

    # Returns a hash of `{ pool_name => init_string }` for all pools in the scope.
    # @return [Hash{Symbol => String}]
    def self.as_hash
      hash = {}
      scoped.each do |zpool|
        hash[zpool.name.to_sym] = zpool.init_string
      end
      hash
    end

    # Creates an LXD storage pool backed by this ZFS pool on the host.
    # @return [Array(Boolean, String)] `[success, output]` from the SSH command
    def create_lxd_storage
      host.exec "lxc storage create #{name.shellescape} zfs source=#{name.shellescape}"
    end
  end
end