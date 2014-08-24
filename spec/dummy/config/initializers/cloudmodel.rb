CloudModel.configure do |config|
  ## Set directory for local stored images etc 
  ## Defaults to "#{Rails.root}/data"
  config.data_directory = Rails.root.join("../../data").to_s
  
  ## Set directory for backups made 
  ## Defaults to "#{data_directory}/backups"
  config.backup_directory = Rails.root.join("../../data/backups").to_s
  
  ## Skip syncing images (Use local compiled images on host)
  ## Defaults to false
  config.skip_sync_images = true
  
  ## Set gentoo mirrors to be used by portage
  ## To find out good servers, run    
  ##   mirrorselect -s4 -H -o 
  ## on a machine running gentoo within the same network as your hosts.  
  ## Defaults to nil
  config.gentoo_mirrors = %w(
    http://linux.rz.ruhr-uni-bochum.de/download/gentoo-mirror/
    http://ftp.fi.muni.cz/pub/linux/gentoo/
    http://ftp-stud.fht-esslingen.de/pub/Mirrors/gentoo/
    http://mirror.netcologne.de/gentoo/
  )
  
  ## Set custom bundle command call 
  ## Defaults to 'PATH=/bin:/sbin:/usr/bin:/usr/local/bin /usr/bin/bundle'
  config.bundle_command = 'bundle'
  
  ## Configure email address of admin for notifications, monitoring
  ## Set to only one email address
  ## if you want to notify more than one, just use a mailing list address.
  ## Defaults to nil
  # config.admin_email = 'admin@example.com'
end