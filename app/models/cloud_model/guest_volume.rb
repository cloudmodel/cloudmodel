module CloudModel
  class GuestVolume
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::BackupTools
    
    belongs_to :guest, class_name: "CloudModel::Guest"
    belongs_to :logical_volume, class_name: "CloudModel::LogicalVolume", inverse_of: :guest_volumes, autobuild: true
    accepts_nested_attributes_for :logical_volume
    
    field :mount_point, type: String
    field :writeable, type: Mongoid::Boolean, default: true
    field :has_backups, type: Mongoid::Boolean, default: false
    
    validates :guest, presence: true
    validates :logical_volume, presence: true
    
    validates :mount_point, presence: true
    validates :mount_point, uniqueness: { scope: :guest }, if: :guest
    validates :mount_point, format: {with: /\A[A-Za-z0-9][A-Za-z0-9\-_\/]*\z/}
    
    before_validation :set_volume_name
    
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
      logical_volume.name = "#{guest.name}-#{mount_point.gsub("/", "-")}"
    end
  end
end