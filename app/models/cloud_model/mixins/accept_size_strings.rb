module CloudModel
  module Mixins
    # Allows Mongoid integer fields to accept human-readable byte-size strings.
    #
    # After including this mixin, call `accept_size_strings_for :field_name` in
    # the class body. The generated setter will convert strings like `"10GB"`,
    # `"512M"`, `"1.5 TiB"` to the equivalent integer number of bytes before
    # storing. Plain integer values and numeric strings (`"1073741824"`) are
    # passed through unchanged.
    #
    # @example
    #   class Guest
    #     include CloudModel::Mixins::AcceptSizeStrings
    #     field :memory_size, type: Integer
    #     accept_size_strings_for :memory_size
    #   end
    #
    #   guest.memory_size = '4GB'   # stored as 4294967296
    module AcceptSizeStrings
      def self.included(base)
        base.extend ClassMethods
      end

      # Converts a human-readable size string to an integer number of bytes.
      #
      # Supported suffixes (case-insensitive): `K`/`KiB`, `M`/`MiB`, `G`/`GiB`,
      # `T`/`TiB`. Raises `"Format unknown"` for unrecognised formats.
      #
      # @param string [String, Numeric] the size value to parse
      # @return [Integer] size in bytes
      # @raise [RuntimeError] if the format is not recognised
      def accept_size_string_parser string
        if string.is_a?(Numeric)
          string
        else
          if string.to_s =~ /^[0-9]+$/
            string.to_i
          elsif string.to_s =~ /^[0-9]+\.?[0-9]*\s?K(iB)?$/
            ((2 ** 10) * string.to_f).to_i
          elsif string.to_s =~ /^[0-9]+\.?[0-9]*\s?M(iB)?$/
            ((2 ** 20) * string.to_f).to_i
          elsif string.to_s =~ /^[0-9]+\.?[0-9]*\s?G(iB)?$/
            ((2 ** 30) * string.to_f).to_i
          elsif string.to_s =~ /^[0-9]+\.?[0-9]*\s?T(iB)?$/
            ((2 ** 40) * string.to_f).to_i
          else
            raise "Format unknown"
          end
        end
      end
    
      module ClassMethods
        # Generates a writer for `field` that passes values through
        # {#accept_size_string_parser} before storing them.
        #
        # @param field [Symbol] the integer field name to enhance
        def accept_size_strings_for field
          define_method "#{field}=" do |size|
            begin
              self[field] = accept_size_string_parser size         
            rescue Exception => e
              CloudModel.log_exception e
              errors.add field, :format
            end
          end
        end
      end
    end
  end
end