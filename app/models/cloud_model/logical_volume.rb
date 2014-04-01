module CloudModel
  class LogicalVolume
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::AcceptSizeStrings
    
    field :name, type: String
    field :disk_space, type: Integer, default: 10737418240
    field :disk_format, type: String, default: 'ext4'
    
    accept_size_strings_for :disk_space
    
    belongs_to :volume_group, class_name: "CloudModel::VolumeGroup", inverse_of: :logical_volumes, autosave: true
    belongs_to :guest, class_name: "CloudModel::Guest", inverse_of: :root_volume
    
    has_many :guest_volumes, class_name: "CloudModel::GuestVolume", inverse_of: :logical_volume
        
    validates :volume_group, presence: true
    validates :name, presence: true, uniqueness: { scope: :volume_group }, format: {with: /\A[a-z0-9\-_]+\z/}
    validates :disk_space, presence: true
    validates :disk_format, presence: true
    
    after_save :apply
    before_destroy :apply_destroy
    
    def to_param
      name
    end
    
    def device
      "#{volume_group.device}/#{name}"
    end
    
    def mapper_device
      "/dev/mapper/#{volume_group.name.gsub('-', '--')}-#{name.gsub('-', '--')}"
    end
    
    def real_info
      volume_group.list_real_volumes[name.to_sym]
    end
    
    def apply
      begin
        data = real_info

        Rails.logger.info "*** LV Data for #{name}: #{data}"

        if data
          if data[:l_size].to_i < disk_space
            # Enlarge LV
            Rails.logger.debug "Enlarge LV"
            volume_group.host.ssh_connection.exec "lvextend #{device.shellescape} --size #{disk_space.to_i}b"
        
            Rails.logger.debug "Enlarge FS"
            volume_group.host.ssh_connection.exec "resize2fs #{device.shellescape}"
          elsif data[:l_size].to_i > disk_space
            # Shrink LV
            Rails.logger.debug "Shrink FS"
            volume_group.host.ssh_connection.exec "e2fsck -f #{device.shellescape} && resize2fs #{device.shellescape} #{(disk_space / 1024.0).floor}K"
        
            Rails.logger.debug "Shrink LV"
            volume_group.host.ssh_connection.exec "lvreduce #{device.shellescape} --size #{disk_space.to_i}b -f"
          end
        else
          # Create LV as it seems not to exist
          Rails.logger.debug "Create LV"    
    
          volume_group.host.ssh_connection.exec "lvcreate -L #{disk_space.to_i}b -n #{name} #{volume_group.device.shellescape}"
  
          Rails.logger.debug "Make FS"
          volume_group.host.ssh_connection.exec "mkfs.#{disk_format.shellescape} #{device.shellescape}"     
        end
      rescue
      end
    end
    
    def apply_destroy
      begin
        data = real_info

        if data
          volume_group.host.ssh_connection.exec "lvremove -f #{device.shellescape}"
        end
      rescue
      end
    end
    
  end
end