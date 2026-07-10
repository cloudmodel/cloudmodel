module CloudModel
  module Mixins
    # Runs shell commands locally on the CloudModel controller machine.
    # Shared by workers, template sync, and migrations — one home for the
    # execute-and-raise semantics.
    module LocalExec
      # @param command [String] shell command
      # @return [String] combined stdout/stderr output
      def local_exec command
        Rails.logger.debug "LOKAL EXEC: #{command}"
        result = %x(#{command} 2>&1)
        Rails.logger.debug "    #{result}"
        result
      end

      # Like {#local_exec} but raises on non-zero exit.
      # @param command [String] shell command
      # @param message [String] error message prefix on failure
      # @return [String] command output
      # @raise [RuntimeError] if the command fails
      def local_exec! command, message
        result = local_exec command

        unless $?.success?
          raise "#{message}: #{result}"
        end
        result
      end
    end
  end
end
