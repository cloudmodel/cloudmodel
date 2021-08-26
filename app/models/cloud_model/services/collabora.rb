module CloudModel
  module Services
    class Collabora < Base
      field :port, type: Integer, default: 9980
      field :wopi_host, type: String, default: nil

      def kind
        :collabora
      end

      def components_needed
        ([:collabora] + super).uniq
      end

      def service_status
        {}
      end

    end
  end
end