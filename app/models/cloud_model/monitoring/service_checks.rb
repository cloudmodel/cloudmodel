module CloudModel
  module Monitoring
    class ServiceChecks < CloudModel::Monitoring::BaseChecks
      def initialize subject, options = {}
        @subject = subject
        @options = options
      end

      def indent_size
        2
      end

      def line_prefix
        "[#{@subject.guest.host.name}] #{super}"
      end

      def data
        @service_check.data if @service_check
      end

      def check
        service_check_class_name = "#{@subject.class.name}Checks".gsub('CloudModel::', 'CloudModel::Monitoring::')
        begin
          service_check_class = service_check_class_name.constantize
        rescue LoadError, NameError => e
          do_check :no_check, "#{service_check_class_name} exists", {info: true}, message: e, value: service_check_class_name
          return false
        end

        do_check :no_check, "#{service_check_class_name} exists", {info: false} # Resolve Issue if Check did not exist before

        if @service_check = service_check_class.new(@subject, @options)
          @service_check.check
        else
          false
        end
      end
    end
  end
end