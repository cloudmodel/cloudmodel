module CloudModel
  module Mixins
    # Adds hex-keyed enum fields to Mongoid documents.
    #
    # Unlike Rails enums (which store string/integer values in a single field),
    # `ENumFields` stores the raw integer key (e.g. `0xf0`) in a `<name>_id`
    # field and exposes a virtual `<name>` accessor that returns the symbol.
    # This allows sparse, non-sequential key assignments (e.g. `0x00`, `0xf0`,
    # `0xff`) without mapping to an ordered array.
    #
    # The enum value is also injected into `serializable_hash` output, replacing
    # the raw `_id` field with the human-readable symbol name.
    #
    # @example
    #   class Guest
    #     include CloudModel::Mixins::ENumFields
    #     enum_field :deploy_state, { 0x00 => :pending, 0xf0 => :finished }, default: :pending
    #   end
    #
    #   guest.deploy_state       # => :pending
    #   guest.deploy_state = :finished
    #   guest.deploy_state_id    # => 240 (0xf0)
    module ENumFields
      def self.included(base)
        base.extend ClassMethods
      end

      module ClassMethods
        # Declares an enum field backed by a Mongoid integer `<name>_id` field.
        #
        # @param name [Symbol] the enum field name (e.g. `:deploy_state`)
        # @param values [Hash{Integer => Symbol}] map of integer key → symbol value
        # @param options [Hash]
        # @option options [Symbol] :default the default symbol value
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

        # Returns the registry of all enum fields declared on the class.
        # @return [Hash{Symbol => Hash}]
        def enum_fields
          @enum_fields ||= {}
        end
      end
    end
  end
end