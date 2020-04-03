module CloudModel
  module Monitoring
    class ServiceChecks < CloudModel::Monitoring::BaseChecks
      def initialize subject, options = {}
        @subject = subject
        
        service_check_class_name = "#{subject.class.name}Checks".gsub('CloudModel::', 'CloudModel::Monitoring::')
        begin
          service_check_class = service_check_class_name.constantize
        rescue LoadError, NameError => e
          do_check :no_check, "#{service_check_class_name} exists", {info: true}, message: e, value: service_check_class_name
          return self
        end

        do_check :no_check, "#{service_check_class_name} exists", {info: false} # Resolve Issue if Check did not exist before
    
        return @service_check = service_check_class.new(subject, options)
      end
      
      def indent_size
        2
      end
    
      def check
        @service_check.check if @service_check
      end
    end
  end
end