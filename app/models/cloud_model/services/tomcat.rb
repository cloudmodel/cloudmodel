module CloudModel
  module Services
    class Tomcat < Base
      field :port, type: Integer, default: 8080
      belongs_to :deploy_war_image, class_name: 'CloudModel::WarImage', inverse_of: :services
      validate :deploy_war_image_id, presence: true
      
      def kind
        :http
      end
      
      def shinken_services_append
        ', tomcat'
      end
    end
  end
end