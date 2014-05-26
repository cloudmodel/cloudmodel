module CloudModel
  class Config 
    attr_writer :data_directory, :backup_directory, :bundle_command
    
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
    
    def bundle_command
      @bundle_command || if Rails.env.test? or Rails.env.development?
        'bundle'        
      else
        'PATH=/bin:/sbin:/usr/bin /usr/local/bin/bundle' 
      end
    end
  end
end