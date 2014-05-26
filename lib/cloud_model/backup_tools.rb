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
      
    end
  end
end