module CloudModel
  class BaseChecks
    
    def store_check_result
      @subject.update_attribute :monitoring_last_check_at, Time.now
      @subject.update_attribute :monitoring_last_check_result, @result
    end
    
    def do_check key, name, checks, options = {}
      issue = @subject.item_issues.find_or_initialize_by key: key, resolved_at: nil
      print "#{' ' * (@indent || 0)}  * Check #{name}... "
      
      if severity = checks.select{|k,v| v}.keys.first
        issue.severity = severity # unless issue.persisted? - check if severity raised?
        issue.message = options[:message]
        issue.value = options[:value]
        issue.save
        puts "[#{severity.to_s.upcase}]"
        false
      else
        issue.resolved_at = Time.now
        issue.save if issue.persisted?
        puts "[OK]"
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