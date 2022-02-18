module CloudModel
  module Components
    class MongodbComponent < BaseComponent
      def human_name
        "MongoDB #{@version}".strip
      end
    end
  end
end