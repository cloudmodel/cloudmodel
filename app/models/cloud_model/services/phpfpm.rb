module CloudModel
  module Services
    class Phpfpm < Base
      field :port, type: Integer, default: 9000
      field :php_components, type: Array, default: []

      def kind
        :phpfpm
      end

      def components_needed
        [:php]
      end

      def available_php_components
        [:php_mysql]
      end

      def service_status

      end
    end
  end
end