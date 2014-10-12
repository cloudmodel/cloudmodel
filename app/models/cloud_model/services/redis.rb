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
    end
  end
end