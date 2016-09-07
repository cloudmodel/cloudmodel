module CloudModel
  module Components
    class Base
      def name
        self.class.name.demodulize.underscore.to_sym
      end
      
      def requirements
        []
      end
    end
  end
end
