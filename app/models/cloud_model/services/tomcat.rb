module CloudModel
  module Services
    class Tomcat < Base
      field :port, type: Integer, default: 8080
      belongs_to :deploy_war_image, class_name: 'CloudModel::WarImage', inverse_of: :services
      validate :deploy_war_image_id, presence: true
      
      def kind
        :http
      end
      
      def components_needed
        [:java, :tomcat]
      end
      
      def shinken_services_append
        ', tomcat'
      end
      
      def livestatus
        if guest.livestatus
          guest.livestatus.services.find{|s| s.description == 'Tomcat'}
        end
      end
      
      def heap_size
        "#{guest.memory_size / 1024 / 1024 - 128}m"
      end
    end
  end
end