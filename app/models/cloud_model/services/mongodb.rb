module CloudModel
  module Services
    class Mongodb < Base
      field :port, type: Integer, default: 27017
      
      def kind
        :mongodb
      end
    end
  end
end