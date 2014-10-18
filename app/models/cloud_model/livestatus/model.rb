require 'socket'

module CloudModel
  module Livestatus
    module Model
      def self.included(base)
        base.send :include, ActiveModel::Conversion  
        base.send :include, ActiveModel::AttributeMethods
        base.extend ActiveModel::Naming  
        base.extend ClassMethods
      end

      def initialize attributes = {}
        @attributes = attributes
       end
    
      module ClassMethods
        def collection
          @collection ||= self.to_s.demodulize.underscore.pluralize
        end
        
        def all options = {}
          Rails.logger.debug "*** Find #{collection} where #{options}"
          
          data = CloudModel::Livestatus::Connection.new.request "GET #{collection}", options
         
          data.map do |attrs|
            self.new attrs
          end
        end
      
        def where condition_hash
          all where: condition_hash
        end
      
        def first
          all.first
        end
      
        def last
          all.last
        end
      
        def count
          all.size
        end
    
        def find id, options = {}
          options[:where] ||= {}
          options[:where].merge! host_name: id
          data = all options
          data.first
        end
      end
      
      def set_attributes attr_hash
        attr_hash.each do |attr, value|
          @attributes[attr] = value
        end  
      end
      
      def perf_data
        data = {}
        pairs = @attributes['perf_data'].split(/[,;]\ /)
        pairs.each do |pair|
          k,v = pair.split('=')
          data[k] = v
        end
        data
      end
      
      def plugin_output
        @attributes['plugin_output'].gsub(/^[A-Z\ ]*[\ \-\:]*/, '')
      end
      
      def method_missing meth, *args, &block
        if @attributes.keys.include? meth.to_s
          @attributes[meth.to_s]
        else
          super # You *must* call super if you don't handle the
                # method, otherwise you'll mess up Ruby's method
                # lookup.
        end
      end
    end
  end
end


