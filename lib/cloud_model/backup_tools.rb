module CloudModel
  module BackupTools 
    def list_backups
      begin
        Dir.entries(backup_directory).select{|x| x.match /\A[0-9]{14}\z/}.sort{|x,y| y<=>x}
      rescue Errno::ENOENT # No backup dir exists or is empty
        return []
      end
    end
    
    def cleanup_backups
      backups = list_backups.sort{|a,b| b<=>a}
      keep_backups = backups[0..2] # always keep last 3 updates
      
      # keep one backup in the last 4 weeks
      (1..4).each do |n|
        keep_backups << backups.select{|x| x > (Time.now - n.weeks).strftime("%Y%m%d%H%M%S")}.first
      end
      # keep one backup in the last 6 month
      (2..6).each do |n|
        keep_backups << backups.select{|x| x > (Time.now - n.months).strftime("%Y%m%d%H%M%S")}.first
      end
      disposible_backups = backups - keep_backups
      
      Rails.logger.debug "Keep backups: #{keep_backups.uniq * ', '}"
      Rails.logger.debug "Dispose backups: #{disposible_backups * ', '}"
      
      disposible_backups.each do |backup|
        FileUtils.rm_rf "#{backup_directory}/#{backup}"
      end
      
      true
    end
  end
end