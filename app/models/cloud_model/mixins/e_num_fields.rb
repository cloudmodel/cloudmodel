module CloudModel
  module Mixins
    module ENumFields
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        def enum_field(name, values, options = {})
          enum_fields[name.to_sym] = options.merge values: values

          attr = "#{name.to_s}_id"

          default_value = if options[:default]
            values.find_all{ |k| k[1] == options[:default].to_sym }.try(:first).try(:first)
          else
            nil
          end

          field attr, type: Integer, default: default_value

          define_method "#{name}=" do |value|
            self.send "#{attr}=", values.find_all{ |k| k[1] == value.to_sym }.try(:first).try(:first)
          end

          define_method "#{name}" do
            values[self.send(attr)]
          end

          define_method "serializable_hash_with_enum_#{name}" do |serialize_options = nil|
            json = self.send "serializable_hash_without_enum_#{name}", serialize_options
            json[name.to_s] = values[json.delete(attr)]
            json
          end

          alias_method "serializable_hash_without_enum_#{name}".to_sym, :serializable_hash# unless method_defined?("serializable_hash_without_enum_#{name}".to_sym)
          alias_method :serializable_hash, "serializable_hash_with_enum_#{name}".to_sym
        end

        def enum_fields
          @enum_fields ||= {}
        end
      end
    end
  end
end