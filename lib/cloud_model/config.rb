module CloudModel
  class Config 
    attr_writer :data_directory, :backup_directory, :bundle_command
    attr_writer :skip_sync_images, :gentoo_mirrors
    
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
    
    # Run `mirrorselect -s4 -H -o` and replace uri Array
    def gentoo_mirrors
      @gentoo_mirrors ||  %w(
        http://linux.rz.ruhr-uni-bochum.de/download/gentoo-mirror/
        http://ftp.fi.muni.cz/pub/linux/gentoo/
        http://ftp-stud.fht-esslingen.de/pub/Mirrors/gentoo/
        http://mirror.netcologne.de/gentoo/
      )
    end
    
    def bundle_command
      @bundle_command || if Rails.env.test? or Rails.env.development?
        'bundle'        
      else
        'PATH=/bin:/sbin:/usr/bin:/usr/local/bin /usr/bin/bundle' 
      end
    end
  end
end