module CloudModel
  module Services
    class Redis < Base
      field :port, type: Integer, default: 6379
      
      def kind
        :redis
      end
      
      def shinken_services_append
        ', redis'
      end
      
      def livestatus
        if guest.livestatus
          guest.livestatus.services.find{|s| s.description == 'Redis'}
        end
      end
      
    end
  end
end