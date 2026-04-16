module CloudModel
  # Abstract base class for web applications that can be mounted at a
  # {WebLocation} inside an Nginx service.
  #
  # Concrete subclasses live in `CloudModel::WebApps::` and registered in
  # {.registered_apps}. Each subclass may override {#needed_components},
  # {#config_files_to_render}, and {#configure} to describe what software and
  # configuration the application needs.
  class WebApp
    include Mongoid::Document
    include Mongoid::Timestamps
    prepend CloudModel::Mixins::SmartToString


    # @!attribute [rw] name
    #   @return [String] human-readable label for this web app instance
    field :name, type: String

    # Returns all concrete WebApp subclasses that can be instantiated.
    # @return [Array<Class>]
    def self.registered_apps
      [
        CloudModel::WebApps::StaticWebApp,
        CloudModel::WebApps::PhpWebApp,
        CloudModel::WebApps::WordpressWebApp,
        CloudModel::WebApps::RoundcubemailWebApp,
        CloudModel::WebApps::NextcloudWebApp
      ]
    end

    # Override in subclasses to declare which component symbols this app requires.
    # @return [Array<Symbol>]
    def needed_components
      []
    end

    # Override in subclasses to declare extra permitted parameters for strong params.
    # @return [Array<Symbol>]
    def additional_allowed_params
      []
    end

    # @return [Mongoid::Criteria<CloudModel::Guest>] guests that host this web app
    def used_in_guests
      CloudModel::Guest.where("services.web_locations.web_app_id" => id)
    end

    # @return [Array<CloudModel::Services::Nginx>] nginx services exposing this app
    def services
      used_in_guests.map do |guest|
        guest.services.where("web_locations.web_app_id" => id).to_a
      end.flatten
    end

    # @return [Array<CloudModel::WebLocation>] all web locations mounting this app
    def web_locations
      services.map do |service|
        service.web_locations.where("web_app_id" => id).to_a
      end.flatten
    end

    # @return [String] snake_case app name derived from the class name
    def self.app_name
      name.demodulize.gsub(/WebApp$/, '').underscore
    end

    # @return [String] absolute path inside the container where the app is installed
    def self.app_folder
      "/opt/web-app/#{app_name}"
    end

    # Override to return a shell command that fetches the application from its source.
    # Returns false by default (no fetch needed).
    # @return [String, false]
    def self.fetch_app_command
      false
    end

    # Override to return a hash of `{ remote_path => template_path }` pairs for
    # config files that should be rendered and written into the container.
    # @return [Hash]
    def config_files_to_render
      {}
    end

    # Override to return a list of shell commands to run during app configuration.
    # @return [Array<String>]
    def configure
      []
    end
  end
end