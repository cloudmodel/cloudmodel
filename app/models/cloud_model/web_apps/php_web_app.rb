module CloudModel
  module WebApps
    class PhpWebApp < ::CloudModel::WebApp
      def needed_components
        [:php]
      end
    end
  end
end