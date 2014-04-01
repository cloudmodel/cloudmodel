module CloudModel
  class GuestVolume
    include Mongoid::Document
    include Mongoid::Timestamps
    
    belongs_to :guest, class_name: "CloudModel::Guest"
    belongs_to :logical_volume, class_name: "CloudModel::LogicalVolume", inverse_of: :guest_volumes, autobuild: true
    accepts_nested_attributes_for :logical_volume
    
    field :mount_point, type: String
    field :writeable, type: Mongoid::Boolean, default: true
    
    validates :guest, presence: true
    validates :logical_volume, presence: true
    
    validates :mount_point, presence: true
    validates :mount_point, uniqueness: { scope: :guest }, if: :guest
    validates :mount_point, format: {with: /\A[A-Za-z0-9][A-Za-z0-9\-_\/]*\z/}
    
    before_validation :set_volume_name
    
    private
    def set_volume_name
      logical_volume.name = "#{guest.name}-#{mount_point.gsub("/", "-")}"
    end
  end
end