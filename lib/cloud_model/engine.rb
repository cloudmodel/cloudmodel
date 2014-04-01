module CloudModel
  class Engine < ::Rails::Engine
    #Rails.logger.debug config.autoload_paths
    config.autoload_paths += Dir["#{config.root}/lib/**/"]
    #Rails.logger.debug config.autoload_paths
  end
end
