module CloudModel
  module Livestatus
    class Host
      include CloudModel::Livestatus::Model
      
      def services
        @services ||= CloudModel::Livestatus::Service.all(where: {host_name: name}, only: %w(host_name description state plugin_output perf_data))
      end
    end
  end
end