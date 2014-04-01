module RSpec
  module Matchers
    class HaveENumMatcher # :nodoc:
      def initialize(*attrs)
        @attributes = attrs.collect(&:to_s)
      end

      def with_values(values)
        @values = values
        self
      end

      def with_default_value_of(default)
        @default = default
        self
      end
    
      def which_is_read_protected
        @read_protected = true
        self
      end

      def which_is_not_read_protected
        @read_protected = false
        self
      end

      def matches?(klass)
        @klass = klass.is_a?(Class) ? klass : klass.class
        @errors = []
        @attributes.each do |attr|
          attr = attr.to_sym
          if @klass.enum_fields.include?(attr)
            error = ""
            if @values and @klass.enum_fields[attr][:values] != @values
              error << " with values #{@klass.enum_fields[attr][:values]}"
            end

            if !@default.nil?
              if @klass.enum_fields[attr][:default].nil?
                error << " with default not set"
              elsif @klass.enum_fields[attr][:default] != @default
                error << " with default value of :#{@klass.enum_fields[attr][:default]}"
              end
            end
            
            @errors.push("enum #{attr.inspect}" << error) unless error.blank?
          
          else
            @errors.push "no enum named #{attr.inspect}"
          end
        end
        @errors.empty?
      end

      def failure_message_for_should
        "Expected #{@klass.inspect} to #{description}, got #{@errors.to_sentence}"
      end

      def failure_message_for_should_not
        "Expected #{@klass.inspect} to not #{description}, got #{@klass.inspect} to #{description}"
      end

      def description
        desc = "have #{@attributes.size > 1 ? 'enums' : 'enum'} named #{@attributes.collect(&:inspect).to_sentence}"
        desc << " with values #{@values.map{|k,v| ":#{v} (#{k})"} * ', '}" if @values
        desc << " with default value of #{@default.inspect}" unless @default.nil?
        desc
      end
    end

    def have_enum(*args)
      HaveENumMatcher.new(*args)
    end
  end
end