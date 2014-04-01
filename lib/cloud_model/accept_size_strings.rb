module CloudModel
  module AcceptSizeStrings
    def self.included(base)
      base.extend ClassMethods
    end
    
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
      def accept_size_strings_for field
        define_method "#{field}=" do |size|
          begin
            self[field] = accept_size_string_parser size         
          rescue
            errors.add field, :format
          end
        end
      end
    end
  end
end