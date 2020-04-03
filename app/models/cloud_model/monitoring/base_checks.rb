module CloudModel
  module Monitoring
    class BaseChecks
      # @param subject [Object] Subject to run checks against
      # @option options [Boolean] :cached (false) Use cached data instead of aquiring it
      # @option options [Boolean] :skip_header (false) Don't display init message
      def initialize subject, options = {}      
        @subject = subject
        @options = options
        
        puts "#{' ' * (indent_size)}[#{subject}]" unless options[:skip_header]
      end
      
      # Config setting indention in spaces for outputs
      def indent_size
        0
      end
    
      # Abstract/Fallback method to aquire data
      # @return nil
      def aquire_data
        nil
      end
    
      # Store the current data to the subject
      def store_data
        attrs = {monitoring_last_check_at: Time.now, monitoring_last_check_result: data}
        @subject.assign_attributes attrs
        res = @subject.collection.update_one({_id: @subject.id}, '$set' => attrs)
        res.ok?
      end

      # Get the data for the subject
      #
      # If the checks have the option :cached set, it uses cached data from the subject
      # Else it will use aquire data and also store it to the subject
      def data
        return @data unless @data.nil?
        
        if @options[:cached]
          @data = @subject.monitoring_last_check_result || false
        else
          print "#{' ' * (indent_size)}  * Acqire data ..."
          @data = aquire_data
          puts "[\e[32mOK\e[39m]"
      
          if @data
            store_data
          end
          @data ||= false
        end
      end



      def do_check key, name, checks, options = {}
        issue = @subject.item_issues.find_or_initialize_by key: key, resolved_at: nil
        print "#{' ' * (indent_size)}  * Check #{name}... "
      
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
          puts "[\e[#{severity_colors[severity]}m#{severity.to_s.upcase}\e[39m]"
          false
        else
          issue.resolved_at = Time.now
          issue.save if issue.persisted?
          puts "[\e[32mOK\e[39m]"
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
          if v
            checks[k] = value > v
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
    end
  end
end