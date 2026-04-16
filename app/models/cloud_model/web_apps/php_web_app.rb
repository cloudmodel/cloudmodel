module CloudModel
  module WebApps
    # Generic PHP web application served via PHP-FPM and nginx.
    #
    # Use this as the base class for custom PHP applications that do not need
    # a more specific web app subclass. Only the `:php` component is required;
    # subclasses should override {#needed_components} to add database or
    # extension dependencies.
    class PhpWebApp < ::CloudModel::WebApp
      # @return [Array<Symbol>] `[:php]`
      def needed_components
        [:php]
      end
    end
  end
end