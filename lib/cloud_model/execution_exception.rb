module CloudModel  
  class ExecutionException < Exception
    attr_accessor :command, :error, :output
    def initialize(command, error, output)
      @command = command
      @error = error
      @output = output
    end
  end
end