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
  
  config.host_mac_address_prefix_init = "44:23"
  
  ## Set custom bundle command call 
  ## Defaults to 'PATH=/bin:/sbin:/usr/bin:/usr/local/bin bundle'
  config.bundle_command = 'bundle'
  
  ## Configure email address of admin for notifications, monitoring
  ## Set to only one email address
  ## if you want to notify more than one, just use a mailing list address.
  ## Defaults to nil
  # config.admin_email = 'admin@example.com'
  
  ## Configure email domain for mail out
  ## Set to only one email domain
  ## Specifies a domain that Exim uses when it constructs a complete email address from a local login name. 
  ## Defaults to nil
  # config.email_domain = 'example.com'
  
  ## Use external IP, useful for testing without setting up a tinc VPN for your development box
  config.use_external_ip = true
end