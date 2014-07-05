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
    
    def exec command
      volume_group.host.exec command
    end
    
    def apply
      begin
        data = real_info

        Rails.logger.debug "*** LV Data for #{name}: #{data}"

        if data
          if data[:l_size].to_i < disk_space
            # Enlarge LV
            Rails.logger.debug "Enlarge LV"
            exec "lvextend #{device.shellescape} --size #{disk_space.to_i}b"
        
            Rails.logger.debug "Enlarge FS"
            exec "resize2fs #{device.shellescape}"
          elsif data[:l_size].to_i > disk_space
            # Shrink LV
            Rails.logger.debug "Shrink FS"
            exec "e2fsck -f #{device.shellescape} && resize2fs #{device.shellescape} #{(disk_space / 1024.0).floor}K"
        
            Rails.logger.debug "Shrink LV"
            exec "lvreduce #{device.shellescape} --size #{disk_space.to_i}b -f"
          end
        else
          # Create LV as it seems not to exist
          Rails.logger.debug "Create LV"    
    
          exec "lvcreate -L #{disk_space.to_i}b -n #{name} #{volume_group.device.shellescape}"
  
          Rails.logger.debug "Make FS"
          exec "mkfs.#{disk_format.shellescape} #{device.shellescape}"     
        end
        
        return true
      rescue Exception => e
        CloudModel.log_exception e
        return false
      end
    end
    
    def apply_destroy
      begin
        data = real_info

        if data
          exec "lvremove -f #{device.shellescape}"
        end
      rescue Exception => e
        CloudModel.log_exception e
        return false
      end
    end
    
    def mounted_on?(mountpoint)
      exec('mount')[1].match(/on #{mountpoint} type/)
    end
    
    def mount mountpoint
      if mounted_on?(mountpoint)
        return true
      end
      success, data = exec "mkdir -p #{mountpoint.shellescape} && mount -t #{disk_format.shellescape} -o noatime #{device.shellescape} #{mountpoint.shellescape}"
      unless success
        raise data
      end
      return success
    end
  end
end