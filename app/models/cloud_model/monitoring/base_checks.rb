module CloudModel
  module Monitoring
    class BaseChecks
      # @param subject [Object] Subject to run checks against
      # @option options [Boolean] :cached (false) Use cached data instead of aquiring it
      # @option options [Boolean] :skip_header (false) Don't display init message
      def initialize subject, options = {}
        @subject = subject
        @options = options

        puts "#{line_prefix}[#{subject}]" unless options[:skip_header]
      end

      # Config setting indention in spaces for outputs
      def indent_size
        0
      end

      # Abstract/Fallback method to acquire data
      # @return nil
      def acquire_data
        nil
      end

      # Store the current data to the subject
      def store_data
        attrs = {monitoring_last_check_at: Time.now, monitoring_last_check_result: data}

        if @subject.update_attributes attrs
          true
        else
          #pp data
          #pp @subject.errors.as_json
          pp data[:system].keys
          #pp data[:system]["labels:sep(0)"]
          data[:system].each do |k,v|
            puts "#{k}: #{v.to_json.size}"
          end
          raise "Failed to store monitoring data"#, "Data:\n #{data}"
        end
        #@subject.update_attributes attrs
      end

      # Get the data for the subject
      #
      # If the checks have the option :cached set, it uses cached data from the subject
      # Else it will use acquire data and also store it to the subject
      def data
        return @data unless @data.nil?

        if @options and @options[:cached]
          @data = @subject.monitoring_last_check_result || false
        else
          puts "#{line_prefix}  * Acqire data ..."
          @data = acquire_data
          puts "#{line_prefix}    -> \e[32mOK\e[39m"

          if @data
            puts "#{line_prefix}  * Store data ..."
            if store_data
              puts "#{line_prefix}    -> \e[32mOK\e[39m"
            else
              puts "#{line_prefix}    -> \e[33mFAILED\e[39m"
            end
          end
          @data ||= false
        end
      end

      def line_prefix
        "#{' ' * (indent_size)}"
      end

      def do_check key, name, checks, options = {}
        issue = @subject.item_issues.find_or_initialize_by key: key, resolved_at: nil
        puts "#{line_prefix}  * Check #{name}... "

        if severity = checks.select{|k,v| v}.keys.first
          issue.severity = severity # unless issue.persisted? - check if severity raised?
          issue.message = options[:message]
          issue.value = options[:value]
          issue.save
          severity_colors = {
            info: 94,
            task: 34,
            warning: 33,
            critical: 31,
            fatal: 35
          }
          puts "#{line_prefix}    -> \e[#{severity_colors[severity]}m#{severity.to_s.upcase}\e[39m"
          false
        else
          issue.resolved_at = Time.now
          issue.save if issue.persisted?
          puts "#{line_prefix}    -> \e[32mOK\e[39m"
          true
        end
      end

      def do_check_value key, value, thresholds, options = {}
        name = options[:name] || key.to_s.humanize
        human_value = if value.is_a? Float
          "#{"%0.2f" % (value)}#{options[:unit]}"
        else
          "#{value}#{options[:unit]}"
        end

        message = options[:message] || "#{name} is #{human_value}"

        checks = {}
        thresholds.each do |k,v|
          if value and v
            checks[k] = value > v
          end
        end

        do_check key, name, checks, message: message, value: human_value
      end

      def do_check_above_value key, value, thresholds, options = {}
        name = options[:name] || key.to_s.humanize
        human_value = if value.is_a? Float
          "#{"%0.2f" % (value)}#{options[:unit]}"
        else
          "#{value}#{options[:unit]}"
        end

        message = options[:message] || "#{name} is #{human_value}"

        checks = {}
        thresholds.each do |k,v|
          if value and v
            checks[k] = value < v
          end
        end

        do_check key, name, checks, message: message, value: human_value
      end

      def do_check_for_errors_on result, error_cases

        error_cases.each do |key, name|
          if result[:key] == key
            severity = result[:severity] || :warning

            do_check result[:key], name, {severity => true}, message: result[:error]
          else
            do_check key, name, {}
          end
        end
      end

      def self.handle_cloudmodel_monitoring_exception subject, host, indent
        begin
          key = :check_crashed
          if subject.is_a? Symbol
            key = "#{key}_#{subject}".to_sym
            subject = nil
          end

          issue = ItemIssue.find_or_initialize_by key: key, resolved_at: nil, subject: subject

          yield
        rescue Exception => e
          prefix = ''
          if host
            if host.is_a? String
              prefix = "[#{host}] "
            else
              prefix = "[#{host.name}] "
            end
          end
          puts "#{prefix}#{(' ' * indent)}\e[33m! Check for #{subject} crashed\e[39m"
          issue.severity = :warning
          issue.message = "#{e.message}\n\n#{e.backtrace * "\n"}"
          issue.value = e.message
          issue.save
          return false
        end
        issue.resolved_at = Time.now
        issue.save if issue.persisted?
        return true
      end
    end
  end
end