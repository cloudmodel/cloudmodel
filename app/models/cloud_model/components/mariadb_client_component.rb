module CloudModel
  module Components
    class MariadbClientComponent < BaseComponent
      def human_name
        "MariaDB Client #{version}".strip
      end
    end
  end
end