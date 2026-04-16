module CloudModel
  module WebApps
    # Web application that serves static files via nginx.
    #
    # No PHP or database components are required. The web root is served
    # directly by nginx without any dynamic processing.
    class StaticWebApp < ::CloudModel::WebApp
    end
  end
end