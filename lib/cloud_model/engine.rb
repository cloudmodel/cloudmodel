module CloudModel
  class Engine < ::Rails::Engine
    initializer 'activeservice.autoload', :before => :set_autoload_paths do |app|
      app.config.paths.add 'app/monitor_checks', glob: '**/*.rb'
      app.config.paths.add 'app/notifiers', glob: '**/*.rb'
      app.config.paths.add 'app/workers', glob: '**/*.rb'
    end
  end
end
