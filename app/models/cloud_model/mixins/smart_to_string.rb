module CloudModel
  module Mixins
    module SmartToString
      def to_s options={}
        "#{model_name.human} '#{name}'"
      end
    end
  end
end