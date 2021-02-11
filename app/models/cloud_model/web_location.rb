module CloudModel
  class WebLocation
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    field :location, type: String, default: '/'

    belongs_to :web_app, class_name: CloudModel::WebApp
    embedded_in :service, class_name: CloudModel::Services::Nginx

    #embedded_in :service, class: CloudModel::Services::Nginx

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
  end
end