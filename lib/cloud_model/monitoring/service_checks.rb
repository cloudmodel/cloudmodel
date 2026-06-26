require_relative "services/base_checks"
Dir[File.expand_path("../services/*", __FILE__)].each { |f| require f }

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
        result = begin
          service_check_class = service_check_class_name.constantize
          do_check :no_check, "#{service_check_class_name} exists", {info: false} # Resolve Issue if Check did not exist before
          @service_check = service_check_class.new(@subject, @options)
          @service_check.check
        rescue LoadError, NameError => e
          do_check :no_check, "#{service_check_class_name} exists", {info: true}, message: e, value: service_check_class_name
          false
        end

        # Backup freshness applies to any backupable service regardless of its
        # service-specific check class (or absence of one).
        check_backup_freshness

        result
      end
    end
  end
end