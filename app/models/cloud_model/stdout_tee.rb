module CloudModel
  # Tees everything a thread writes to $stdout while a block runs into a
  # +sink+ (the live console of a guest, template or web image), in addition
  # to the original stdout.
  #
  # $stdout is process-global, the captures are not: a batch deploy runs one
  # worker per host in parallel threads, each capturing into its own guest's
  # console. So a single dispatcher stands in for $stdout while any capture is
  # active and routes each write by the sinks of the *writing* thread — a
  # thread that captures nothing writes straight to the terminal. Nested
  # captures in one thread feed every sink on the stack (a quiet per-guest
  # rollout log inside a web image rollout must not starve the outer log);
  # only the outermost capture decides whether the terminal sees the output.
  class StdoutTee
    MUTEX = Mutex.new
    @active = 0

    class << self
      # @param sink [Proc] called with every written string
      # @param passthrough [Boolean] also write to the original stdout; false
      #   keeps the console quiet — the output only reaches the sink
      def capture sink, passthrough: true
        stack = (Thread.current[:cloud_model_stdout_tee] ||= [])
        MUTEX.synchronize do
          if @active == 0
            @original = $stdout
            $stdout = new(@original)
          end
          @active += 1
        end
        stack.push [sink, passthrough]
        yield
      ensure
        stack.pop
        MUTEX.synchronize do
          @active -= 1
          if @active == 0
            $stdout = @original
            @original = nil
          end
        end
      end

      # Whether the current thread's output is being captured (used by
      # workers to decide whether to echo commands into the console).
      def capturing?
        stack = Thread.current[:cloud_model_stdout_tee]
        !(stack.nil? || stack.empty?)
      end
    end

    def initialize original
      @original = original
    end

    def write *args
      args.sum do |arg|
        # Worker output arrives as raw bytes (Net::SSH) and may carry anything
        # a remote tool prints — the RVM installer's "🙏", for one. Hand on
        # valid UTF-8 only: a console stdout with an internal encoding
        # (the Rails console) raises Encoding::UndefinedConversionError on
        # raw high bytes, and nothing written here may ever fail the flow.
        text = arg.to_s.dup.force_encoding(Encoding::UTF_8).scrub('?')
        stack = Thread.current[:cloud_model_stdout_tee] || []
        stack.each do |sink, _passthrough|
          begin
            sink.call text
          rescue => e
            Rails.logger.warn "StdoutTee sink failed: #{e.message}"
          end
        end
        passthrough = stack.empty? || stack.first[1]
        if passthrough
          begin
            @original.write text
          rescue => e
            Rails.logger.warn "StdoutTee passthrough failed: #{e.message}"
            text.bytesize
          end
        else
          text.bytesize
        end
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
