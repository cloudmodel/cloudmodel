module CloudModel
  module Mixins
    module BackupTools 
      def list_backups
        begin
          Dir.entries(backup_directory).select{|x| x.match /\A[0-9]{14}\z/}.sort{|x,y| y<=>x}
        rescue Errno::ENOENT # No backup dir exists or is empty
          return []
        end
      end
    
      def list_disposable_backups
        backups = list_backups.sort{|a,b| b<=>a}
      
        #puts "\n ALL #{backups * ', '}"
      
        now = Time.now
      
        keep_backups = backups[0..2] # always keep last 3 updates
      
        # keep all backups in the last 3 days
        keep_backups += backups.select{|x| x >= (now - 3.days).strftime("%Y%m%d%H%M%S")}
      
        # limit backups to the last 6 month (exept less than 3)
        last_backups = backups.select{|x| x >= (now - 6.month).strftime("%Y%m%d%H%M%S")}
      
        # keep one backup each for the last 6 days
        (3..6).each do |n|
          keep = last_backups.select{|x| x <= (now - (n+1).days).strftime("%Y%m%d%H%M%S")}.first
          #puts "Keep for Day    #{n} (#{(now - (n+1).days).strftime("%Y%m%d%H%M%S")}): #{keep}"
          keep_backups << keep
        end
      
        # keep one backup each for the last 6 weeks
        (1..6).each do |n|
          keep = last_backups.select{|x| x <= (now - (n+1).weeks).strftime("%Y%m%d%H%M%S")}.first
          #puts "Keep for Week   #{n} (#{(now - (n+1).weeks).strftime("%Y%m%d%H%M%S")}): #{keep}"
          keep_backups << keep
        end
        # keep one backup each for the last 6 month
        (1..6).each do |n|
          keep = last_backups.select{|x| x <= (now - (n+1).month).strftime("%Y%m%d%H%M%S")}.first
          #puts "Keep for Month #{"%2d" % n} (#{(now - (n+1).month).strftime("%Y%m%d%H%M%S")}): #{keep}"
          keep_backups << keep
        end
        disposible_backups = backups - keep_backups
      
        Rails.logger.debug "Keep backups: #{keep_backups.uniq * ', '}"
        Rails.logger.debug "Dispose backups: #{disposible_backups * ', '}"
        #puts "KEEP #{keep_backups.uniq * ', '}"
        #puts "DISP #{disposible_backups * ', '}"
      
        disposible_backups
      end
    
      def cleanup_backups  
        list_disposable_backups.each do |backup|
          FileUtils.rm_rf "#{backup_directory}/#{backup}"
        end
      
        true
      end
    end
  end
end