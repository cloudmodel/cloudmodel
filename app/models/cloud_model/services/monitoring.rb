module CloudModel
  module Services
    class Monitoring < Base
      field :graphite_web_enabled, type: Boolean, default: false
      
      def kind
        :monitoring
      end
    end
  end
end