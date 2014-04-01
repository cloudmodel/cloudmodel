module CloudModel
  module Services
    class Base
      include Mongoid::Document
      include Mongoid::Timestamps
  
      field :name, type: String    
      field :public_service, type: Mongoid::Boolean, default: false
   
      embedded_in :guest, class_name: "CloudModel::Guest", inverse_of: :services
  
      def self.service_types 
        {
          mongodb: 'CloudModel::Services::Mongodb',
          nginx: 'CloudModel::Services::Nginx',
          redis: 'CloudModel::Services::Redis',
          ssh: 'CloudModel::Services::Ssh',
          tomcat: 'CloudModel::Services::Tomcat'
        }
      end
    
      def used_ports
        [port]
      end
    
      def kind
        :unknown
      end
    end
  end
end
