module CloudModel
  module Services
    class Ssh < Base
      field :port, type: Integer, default: 22
      field :authorized_keys, type: Array
      
      # TODO: Handle authorized_keys presets
      
      def kind
        :ssh
      end
      
      def components_needed
        [] # ssh is default to core
      end
      
      def shinken_services_append
        ', ssh'
      end
      
      def livestatus
        if guest.livestatus
          guest.livestatus.services.find{|s| s.description == 'Ssh'}
        end
      end
    end
  end
end