module CloudModel
  class Config 
    attr_writer :data_directory, :backup_directory, :bundle_command
    attr_writer :skip_sync_images, :gentoo_mirrors
    attr_writer :xmmp_port
    attr_accessor :xmmp_server, :xmmp_user, :xmmp_password

    attr_accessor :admin_email, :admin_xmmp, :email_domain, :gentoo_mirrors
    attr_accessor :livestatus_host
    attr_writer :livestatus_port
    
    def initialize(&block) 
      configure(&block) if block_given?
    end

    # Configure your CloudModel Rails Application with the given parameters in 
    # the block. For possible options see above.
    def configure(&block)
      yield(self)
    end
    
    def data_directory
      @data_directory || "#{Rails.root}/data"
    end
    
    def backup_directory
      @backup_directory || "#{data_directory}/backups"
    end
    
    # If true do not sync images on deploy
    def skip_sync_images
      @skip_sync_images || false
    end
    
    def bundle_command
      @bundle_command || 'PATH=/bin:/sbin:/usr/bin:/usr/local/bin bundle'
    end
    
    def xmmp_port
      @xmmp_port || 5222
    end
    
    def uses_xmmp?
      xmmp_server && xmmp_user && admin_xmmp
    end
    
    def livestatus_port
      @livestatus_port || 50000
    end
  end
end