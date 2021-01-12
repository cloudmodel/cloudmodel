module CloudModel
  module Services
    class Phpfpm < Base
      field :port, type: Integer, default: 22

      # TODO: Handle authorized_keys presets

      def kind
        :phpfpm
      end

      def components_needed
        [:php]
      end

      def service_status

      end
    end
  end
end