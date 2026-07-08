module CloudModel
  # Tees everything written to $stdout while the block runs into +sink+, in
  # addition to the original stdout. Swapping $stdout is process-global —
  # acceptable here: the delayed_job worker runs one job at a time, and rake
  # flows own their process.
  class StdoutTee
    # @param sink [Proc] called with every written string
    # @param passthrough [Boolean] also write to the original stdout; false
    #   keeps the console quiet — the output only reaches the sink
    def self.capture sink, passthrough: true
      original = $stdout
      # A nested capture must keep feeding the outer one — only the OUTERMOST
      # capture decides whether the terminal sees the output. Without this a
      # quiet inner capture (e.g. a per-guest rollout log inside a web image
      # rollout) would starve the outer log.
      passthrough = true if original.is_a? self
      $stdout = new(original, sink, passthrough: passthrough)
      yield
    ensure
      $stdout = original
    end

    def initialize original, sink, passthrough: true
      @original = original
      @sink = sink
      @passthrough = passthrough
    end

    def write *args
      args.sum do |arg|
        text = arg.to_s
        begin
          @sink.call text
        rescue => e
          Rails.logger.warn "StdoutTee sink failed: #{e.message}"
        end
        @passthrough ? @original.write(text) : text.bytesize
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
