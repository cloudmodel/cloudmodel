module CloudModel
  module Components
    class NginxComponent < BaseComponent
      def human_name
        "NGINX #{version}".strip
      end
    end
  end
end