module CloudModel
  class Zpool
    include Mongoid::Document
    include Mongoid::Timestamps

    embedded_in :host, :polymorphic => true

    field :name, type: String
    field :init_string, type: String

    validates :name, presence: true, uniqueness: true

    def self.as_hash
      hash = {}
      scoped.each do |zpool|
        hash[zpool.name.to_sym] = zpool.init_string
      end
      hash
    end

    def create_lxd_storage
      host.exec "lxc storage create #{name.shellescape} zfs source=#{name.shellescape}"
    end
  end
end