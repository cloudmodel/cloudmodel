module CloudModel
  class Engine < ::Rails::Engine
    # initializer 'activeservice.autoload', :before => :set_autoload_paths do |app|
    #   app.config.paths.add 'app/monitor_checks', glob: '**/*.rb'
    #   app.config.paths.add 'app/notifiers', glob: '**/*.rb'
    #   app.config.paths.add 'app/workers', glob: '**/*.rb'
    # end

    # Mongoid resolves a polymorphic belongs_to (WebLocation#web_app, stored
    # as "CloudModel::WebApps::…") through its registry of *loaded* models,
    # not by constantizing the name. Rake tasks and runners boot without eager
    # loading, so the first guest with such a web location raised
    # UnrecognizedModelAlias there (e.g. in Guest#components_needed), although
    # the class exists. Load the namespace up front in every boot mode.
    config.to_prepare do
      Rails.autoloaders.main.eager_load_namespace(CloudModel::WebApps)
    end
  end
end
