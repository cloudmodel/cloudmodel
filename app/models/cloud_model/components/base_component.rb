module CloudModel
  module Components
    class BaseComponent
      attr_accessor :version

      def initialize options={}
        @version = options[:version]
      end

      def self.from_sym sym
        component_name, component_version = sym.to_s.split('@')
        component_class = "CloudModel::Components::#{component_name.to_s.camelcase}Component".constantize

        component_class.new(version: component_version)
      end

      def base_name
        self.class.name.demodulize.underscore.gsub(/_component$/, '')
      end

      def name
        name = base_name

        if(version)
          name += "@#{version}"
        end

        name.to_sym
      end

      def human_name
        "#{base_name.camelcase} #{version}".strip
      end

      def worker template, host, options = {}
        worker_class = "CloudModel::Workers::Components::#{base_name.to_s.gsub(/[^a-z0-9_]*/, '').camelcase}ComponentWorker".constantize
        worker_class.new template, host, options.merge(component: self)
      end

      def requirements
        []
      end
    end
  end
end
