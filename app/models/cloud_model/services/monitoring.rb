module CloudModel
  module Services
    class Monitoring < Base
      field :graphite_web_enabled, type: Boolean, default: false
      
      def kind
        :monitoring
      end
      
      def port
        7767
      end
    end
  end
end