module CloudModel
  module Services
    class Ssh < Base
      field :port, type: Integer, default: 22
      field :authorized_keys, type: Array
      
      # TODO: Handle authorized_keys presets
      
      def kind
        :ssh
      end
    end
  end
end