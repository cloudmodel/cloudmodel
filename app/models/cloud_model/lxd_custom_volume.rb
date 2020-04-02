module CloudModel
  class LxdCustomVolume
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::AcceptSizeStrings
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString
    
    embedded_in :guest, class_name: "CloudModel::Guest"
    
    field :name, type: String
    field :disk_space, type: Integer, default: 10737418240

    field :mount_point, type: String
    field :writeable, type: Mongoid::Boolean, default: true    
    field :has_backups, type: Mongoid::Boolean, default: false
        
    validates :name, presence: true
    validates :name, uniqueness: { scope: :host }
    validates :name, format: {with: /\A[A-Za-z0-9][A-Za-z0-9\-_]*\z/}
    
    validates :mount_point, presence: true
    validates :mount_point, uniqueness: { scope: :guest }
    validates :mount_point, format: {with: /\A[A-Za-z0-9][A-Za-z0-9\-_\/]*\z/}

    accept_size_strings_for :disk_space

    before_validation :set_volume_name       
    after_create :create_volume!
    before_destroy :before_destroy
    
    def host
      guest.host
    end
    
    def before_destroy
      if used?
        puts "Can't destroy attached volume; unattach it first"
        return false
      end

      success, output = destroy_volume
      unless success
        puts "Failed to destroy LXD volume"
      end
      success
    end
    
    def volume_exists?
      success, output = lxc "storage volume show default #{name.shellescape}"
      not(success == false and output == "Error: not found\n")
    end
    
    def create_volume
      lxc "storage volume create default #{name.shellescape}"
    end
    
    def create_volume!
      lxc! "storage volume create default #{name.shellescape}", "Failed to init LXD volume"     
    end
    
    def destroy_volume
      lxc "storage volume delete default #{name.shellescape}" 
    end
    
    def to_param
      name
    end
    
    def item_issue_chain
      [host, guest, self]
    end
    
    # Get infos about the volume
    def lxc_show
      success, result = lxc "storage volume show default #{name.shellescape}"
      if success
        YAML.load(result).deep_transform_keys { |key| key.to_s.underscore }
      else
        nil
      end
    end
    
    def used?
      result = lxc_show
      result && result['used_by'] && result['used_by'].size > 0
    end
    
    def host_path
      "/var/lib/lxd/storage-pools/default/custom/#{name}/"
    end
    
    # Backup 
    
    def backup_directory
      "#{CloudModel.config.backup_directory}/#{host.id}/#{guest.id}/volumes/#{id}"
    end
    
    def backup
      return false unless has_backups
      timestamp = Time.now.strftime "%Y%m%d%H%M%S"
      FileUtils.mkdir_p backup_directory
      command = "rsync -avz " +
        "-e 'ssh -o StrictHostKeyChecking=no -i #{CloudModel.config.data_directory.shellescape}/keys/id_rsa' " +
        "--partial --link-dest=#{backup_directory.shellescape}/latest " +
        "root@#{host.private_network.list_ips.first}:#{host_path.shellescape}/ " +
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
        "root@#{host.private_network.list_ips.first}:#{host_path.shellescape}"
        
      Rails.logger.debug command
      Rails.logger.debug `#{command}`
      $?.success?
    end
    
    private
    def set_volume_name
      self.name = "#{guest.name}-#{mount_point.gsub("/", "-")}"
    end
    
    def lxc command
      host.exec "lxc #{command}"
    end
    
    def lxc! command, error
      host.exec! "lxc #{command}", error
    end    
  end
end
