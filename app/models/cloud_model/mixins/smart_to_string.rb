module CloudModel
  module Mixins
    # Provides a human-readable `#to_s` implementation for Mongoid models.
    #
    # The default `to_s` returns a string in the format
    # `"<HumanModelName> '<name>'"`, e.g. `"Guest 'app-01'"`.
    # Models that include this mixin must have a `#name` method.
    #
    # Prepend (not include) this module so that subclasses can still call
    # `super` to customise the format.
    module SmartToString
      # @return [String] e.g. `"Guest 'app-01'"`
      def to_s options={}
        "#{model_name.human} '#{name}'"
      end
    end
  end
end