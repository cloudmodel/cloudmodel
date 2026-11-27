module CloudModel
  module Components
    # MySQL Community Server from MySQL's own apt repository. The version is
    # the release series, e.g. `mysql@8.4`.
    class MysqlComponent < BaseComponent
      def human_name
        "MySQL #{version}".strip
      end
    end
  end
end
