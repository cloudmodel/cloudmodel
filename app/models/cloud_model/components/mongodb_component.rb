module CloudModel
  module Components
    # Component that installs MongoDB into a guest template.
    class MongodbComponent < BaseComponent
      # @return [String] e.g. `"MongoDB 7.0"`
      def human_name
        "MongoDB #{@version}".strip
      end
    end
  end
end