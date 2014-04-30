module CloudModel
  class VolumeGroup
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::AcceptSizeStrings
    
    belongs_to :host, class_name: "CloudModel::Host", inverse_of: :volume_groups
    has_many :logical_volumes, class_name: "CloudModel::LogicalVolume", inverse_of: :volume_group
    
    field :name, type: String
    field :disk_device, type: String
    field :disk_space, type: Integer
    
    accept_size_strings_for :disk_space
    
    validates :name, presence: true, uniqueness: { scope: :host }, format: {with: /\A[a-z0-9]+\z/}
    validates :disk_device, presence: true, uniqueness: { scope: :host }, format: {with: /\A[a-z0-9]+\z/}
    #validates :disk_space, presence: true
    
    after_create :apply_create
    
    def available_space
      disk_space - logical_volumes.sum(:disk_space)
    end
    
    def device
      "/dev/#{name}"
    end
    
    def to_param
      name
    end
    
    def real_info
      host.list_real_volume_groups[name.to_sym]
    end
    
    def exec command
      host.exec command
    end
    
    def list_real_volumes
      begin
        success, result = exec "lvs --separator ';' --units b --nosuffix --all -o lv_all #{name.shellescape}"
        volume_groups = {}
    
        lines = result.split("\n")
        head = lines.shift.split(";").map{|c| c.strip.sub('#', '').gsub(' ', '_').gsub(/\%$/, '_percentage').gsub('%', '_percentage_').underscore.to_sym}

        lines.each do |row|
          columns = row.split(";")
          row_hash = {}
          head.each do |n|
            value = columns.shift
            row_hash[n] = value.strip if value
          end
      
          name = row_hash.delete(:lv).to_sym
          volume_groups[name] = row_hash
        end
      
        return volume_groups
      rescue Exception => e
        CloudModel.log_exception e
        return false
      end
    end
    
    def apply_create
      exec "pvcreate /dev/#{disk_device.shellescape}" || raise('Failed to create virtual space')
      exec "vgcreate #{name.shellescape} /dev/#{disk_device.shellescape}" || raise('Failed to create lvm volume group')
    end
  end
end