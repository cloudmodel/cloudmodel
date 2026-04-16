module CloudModel
  # Maps a URL path on an Nginx service to a {WebApp} instance.
  #
  # WebLocations are embedded inside {Services::Nginx} documents. Each location
  # defines a path (e.g. `"/"` or `"/wiki"`) and references a {WebApp} subclass
  # that supplies the nginx location block configuration.
  class WebLocation
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] location
    #   @return [String] URL path prefix, e.g. `"/"` or `"/nextcloud"` (default: `"/"`)
    field :location, type: String, default: '/'

    # @!attribute [rw] web_app
    #   @return [CloudModel::WebApp] the web application served at this path (polymorphic)
    belongs_to :web_app, class_name: CloudModel::WebApp, polymorphic: true

    # @!attribute [rw] service
    #   @return [CloudModel::Services::Nginx] the nginx service this location belongs to
    embedded_in :service, class_name: CloudModel::Services::Nginx

    #embedded_in :service, class: CloudModel::Services::Nginx

    # Returns the location string with both a leading and a trailing slash.
    # @return [String] e.g. `"/nextcloud/"`
    def location_with_slashes
      l = "#{location}"

      if l.first != '/'
        l = "/#{l}"
      end

      if l.last != '/'
        l = "#{l}/"
      end

      l
    end

    # Returns the location with a leading slash and no trailing slash.
    # @return [String] e.g. `"/nextcloud"`
    def location_with_leading_slash
      l = "#{location}"

      if l.last == '/'
        l = l.gsub(/\/$/, '')
      end

      if l.first != '/'
        l = "/#{l}"
      end

      l
    end

    # Returns the full public URL for this web location.
    # @return [String] e.g. `"https://example.com/nextcloud/"`
    def base_uri
      "http#{service.ssl_supported? ? 's' : ''}://#{service.guest.external_hostname}#{location_with_slashes}"
    end
  end
end