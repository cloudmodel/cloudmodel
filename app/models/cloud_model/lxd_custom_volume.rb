module CloudModel
  class LxdCustomVolume
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::AcceptSizeStrings
    include CloudModel::ModelHasIssues
    prepend CloudModel::SmartToString
    
    embedded_in :guest, class_name: "CloudModel::Guest"
    
    field :name, type: String
    field :disk_space, type: Integer, default: 10737418240

    field :mount_point, type: String
    field :writeable, type: Mongoid::Boolean, default: true    
    field :has_backups, type: Mongoid::Boolean, default: false
        
    validates :mount_point, presence: true
    validates :mount_point, uniqueness: { scope: :guest }, if: :guest
    validates :mount_point, format: {with: /\A[A-Za-z0-9][A-Za-z0-9\-_\/]*\z/}

    accept_size_strings_for :disk_space

    before_validation :set_volume_name       
    after_create :create_volume!
    before_destroy :before_destroy
    
    def before_destroy
      if used?
        puts "Can't destroy attached volume; unattach it first"
        return false
      end

      destroy_volume
    end
    
    def volume_exists?
      res, output = lxc "storage volume show default #{name}"
      not(res == false and output == "Error: not found\n")
    end
    
    def create_volume
      lxc "storage volume create default #{name}"
    end
    
    def create_volume!
      lxc! "storage volume create default #{name}", "Failed to init LXD volume"     
    end
    
    def destroy_volume
      lxc! "storage volume delete default #{name}", "Failed to destroy LXD volume"     
    end
    
    def to_param
      name
    end
    
    # Get infos about the volume
    def lxc_show
      success, result = lxc "storage volume show default #{name}"
      YAML.load(result).deep_transform_keys { |key| key.to_s.underscore }
    end
    
    def used?
      lxc_show['used_by'] && lxc_show['used_by'].size > 0
    end
    
    # Backup 
    
    def backup_directory
      "#{CloudModel.config.backup_directory}/#{guest.host.id}/#{guest._id}/volumes/#{_id}"
    end
    
    def backup
      return false unless has_backups
      timestamp = Time.now.strftime "%Y%m%d%H%M%S"
      FileUtils.mkdir_p backup_directory
      command = "rsync -avz " +
        "-e 'ssh -o StrictHostKeyChecking=no -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa' " +
        "--partial --link-dest=#{backup_directory.shellescape}/latest " +
        "root@#{guest.host.private_network.list_ips.first}:#{guest.base_path.shellescape}/#{mount_point.shellescape}/ " +
        "#{backup_directory.shellescape}/#{timestamp}"
        
      Rails.logger.debug command
      Rails.logger.debug `#{command}`
      
      if $?.success? and File.exists? "#{backup_directory}/#{timestamp}"
        FileUtils.rm_f "#{backup_directory}/latest"
        FileUtils.ln_s "#{backup_directory}/#{timestamp}", "#{backup_directory}/latest"
        cleanup_backups
        
        return true
      else
        FileUtils.rm_rf "#{backup_directory}/#{timestamp}"
        return false
      end
      
    end
    
    def restore timestamp='latest'
      command = "rsync -avz " +
        "-e 'ssh -o StrictHostKeyChecking=no -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa' "+
        "--delete " +
        "#{backup_directory.shellescape}/#{timestamp}/ "+
        "root@#{guest.host.private_network.list_ips.first}:#{guest.base_path.shellescape}/#{mount_point.shellescape}"
        
      Rails.logger.debug command
      Rails.logger.debug `#{command}`
      $?.success?
    end
    
    private
    def set_volume_name
      self.name = "#{guest.name}-#{mount_point.gsub("/", "-")}"
    end
    
    def lxc command
      guest.host.exec "lxc #{command}"
    end
    
    def lxc! command, error
      guest.host.exec! "lxc #{command}", error
    end    
  end
end
