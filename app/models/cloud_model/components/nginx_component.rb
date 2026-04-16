module CloudModel
  module Components
    # Component that installs nginx into a guest template.
    class NginxComponent < BaseComponent
      def human_name
        "NGINX #{version}".strip
      end
    end
  end
end