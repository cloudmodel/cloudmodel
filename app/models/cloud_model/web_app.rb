module CloudModel
  class WebApp
    include Mongoid::Document
    include Mongoid::Timestamps
    prepend CloudModel::Mixins::SmartToString


    field :name, type: String

    def self.registered_apps
      [
        CloudModel::WebApps::StaticWebApp,
        CloudModel::WebApps::PhpWebApp,
        CloudModel::WebApps::WordpressWebApp,
        CloudModel::WebApps::RoundcubemailWebApp,
        CloudModel::WebApps::NextcloudWebApp
      ]
    end

    def needed_components
      []
    end

    def additional_allowed_params
      []
    end

    def self.app_name
      name.demodulize.gsub(/WebApp$/, '').underscore
    end

    def self.app_folder
      "/opt/web-app/#{app_name}"
    end

    def self.fetch_app_command
      false
    end

    def self.config_files_to_render
      {}
    end
  end
end