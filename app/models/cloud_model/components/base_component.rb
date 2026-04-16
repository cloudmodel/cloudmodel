module CloudModel
  module Components
    # Abstract base class for all CloudModel guest components.
    #
    # A component represents a named software package (nginx, ruby, solr, …)
    # that can be installed into a guest template. Components are referenced
    # by symbol, optionally with a version suffix separated by `@`:
    #
    #   :nginx          # version-less
    #   :"solr@9.4"     # pinned to version 9.4
    #
    # {BaseComponent.from_sym} resolves a symbol to the concrete subclass and
    # instantiates it. Each subclass may override {#requirements} to declare
    # other components that must be installed first, and may override
    # {#human_name} for display purposes.
    class BaseComponent
      # @!attribute [rw] version
      #   @return [String, nil] optional version string supplied via the `@version` suffix
      attr_accessor :version

      def initialize options={}
        @version = options[:version]
      end

      # Resolves a component symbol to an instance of the correct subclass.
      #
      # @param sym [Symbol] component identifier, e.g. `:nginx` or `:"solr@9.4"`
      # @return [BaseComponent] instantiated component with {#version} set
      def self.from_sym sym
        component_name, component_version = sym.to_s.split('@')
        component_class = "CloudModel::Components::#{component_name.to_s.camelcase}Component".constantize

        component_class.new(version: component_version)
      end

      # @return [String] snake_case component name without the `_component` suffix
      def base_name
        self.class.name.demodulize.underscore.gsub(/_component$/, '')
      end

      # @return [Symbol] component symbol, including `@version` suffix when set
      def name
        name = base_name

        if(version)
          name += "@#{version}"
        end

        name.to_sym
      end

      # @return [String] human-readable display name, e.g. `"NGINX"` or `"PHP 8.2"`
      def human_name
        "#{base_name.camelcase} #{version}".strip
      end

      # Instantiates the worker responsible for installing this component.
      #
      # @param template [CloudModel::GuestTemplate] target guest template
      # @param host [CloudModel::Host] host on which installation runs
      # @param options [Hash] additional options forwarded to the worker
      # @return [CloudModel::Workers::Components::BaseComponentWorker] worker instance
      def worker template, host, options = {}
        worker_class = "CloudModel::Workers::Components::#{base_name.to_s.gsub(/[^a-z0-9_]*/, '').camelcase}ComponentWorker".constantize
        worker_class.new template, host, options.merge(component: self)
      end

      # @return [Array<Symbol>] list of component symbols that must be installed
      #   before this component; empty by default
      def requirements
        []
      end
    end
  end
end
