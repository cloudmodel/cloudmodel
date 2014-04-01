module CloudModel
  class VolumeGroup
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::AcceptSizeStrings
    
    belongs_to :host, class_name: "CloudModel::Host", inverse_of: :volume_groups
    has_many :logical_volumes, class_name: "CloudModel::LogicalVolume", inverse_of: :volume_group
    
    field :name, type: String
    field :device, type: String
    field :disk_space, type: Integer
    
    accept_size_strings_for :disk_space
    
    validates :name, presence: true, uniqueness: { scope: :host }, format: {with: /\A[a-z0-9]+\z/}
    validates :device, presence: true, uniqueness: { scope: :host }
    validates :disk_space, presence: true
    
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
    
    def list_real_volumes
      begin
        result = host.ssh_connection.exec "lvs --separator ';' --units b --nosuffix --all -o lv_all #{name.shellescape}"
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
      rescue
      end
    end
  end
end