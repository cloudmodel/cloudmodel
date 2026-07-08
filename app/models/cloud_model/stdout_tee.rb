module CloudModel
  # Tees everything written to $stdout while the block runs into +sink+, in
  # addition to the original stdout. Swapping $stdout is process-global —
  # acceptable here: the delayed_job worker runs one job at a time, and rake
  # flows own their process.
  class StdoutTee
    # @param sink [Proc] called with every written string
    def self.capture sink
      original = $stdout
      $stdout = new(original, sink)
      yield
    ensure
      $stdout = original
    end

    def initialize original, sink
      @original = original
      @sink = sink
    end

    def write *args
      args.sum do |arg|
        text = arg.to_s
        begin
          @sink.call text
        rescue => e
          Rails.logger.warn "StdoutTee sink failed: #{e.message}"
        end
        @original.write text
      end
    end

    def << text
      write text
      self
    end

    # Kernel#puts/print go through $stdout.puts/$stdout.print — implement
    # them on top of #write so the sink sees them too (plain delegation via
    # method_missing would bypass it).
    def puts *args
      if args.empty?
        write "\n"
      else
        args.flatten.each do |arg|
          text = arg.to_s
          text += "\n" unless text.end_with? "\n"
          write text
        end
      end
      nil
    end

    def print *args
      args.each { |arg| write arg.to_s }
      nil
    end

    def method_missing name, *args, &block
      @original.send name, *args, &block
    end

    def respond_to_missing? name, include_private = false
      @original.respond_to? name, include_private
    end
  end
end
