module CloudModel
  module Services
    class Tomcat < Base
      field :port, type: Integer, default: 8080
      belongs_to :deploy_war_image, class_name: 'CloudModel::WarImage', inverse_of: :services
      
      def kind
        :http
      end
    end
  end
end