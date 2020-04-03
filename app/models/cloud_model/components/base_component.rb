module CloudModel
  module Components
    class BaseComponent
      def name
        self.class.name.demodulize.underscore.gsub(/_component$/, '').to_sym
      end
      
      def requirements
        []
      end
    end
  end
end
