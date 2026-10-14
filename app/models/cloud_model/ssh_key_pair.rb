require 'shellwords'
require 'fileutils'

module CloudModel
  # An SSH key pair on the controller machine that is created on first use.
  # Nothing in CloudModel requires generating keys by hand: whoever needs a
  # pair calls {#ensure!} and gets one (see {ZfsSyncKey} and the controller's
  # own host key in {Workers::HostWorker}).
  class SshKeyPair
    include CloudModel::Mixins::LocalExec

    attr_reader :private_key_file, :type, :bits, :comment

    # @param private_key_file [String] path of the private key; the public
    #   key lives beside it as `<path>.pub`
    # @param type [String] ssh-keygen key type
    # @param bits [Integer, nil] key size (rsa only)
    # @param comment [String, nil] key comment (`-C`)
    def initialize private_key_file, type: 'ed25519', bits: nil, comment: nil
      @private_key_file = private_key_file
      @type = type
      @bits = bits
      @comment = comment
    end

    def public_key_file
      "#{private_key_file}.pub"
    end

    def present?
      File.exist?(private_key_file) and File.exist?(public_key_file)
    end

    # Generates the pair unless both halves exist.
    # @return [true]
    def ensure!
      return true if present?

      FileUtils.mkdir_p File.dirname(private_key_file)
      command = ["ssh-keygen -q -N '' -t #{type.shellescape}"]
      command << "-b #{bits.to_i}" if bits
      command << "-C #{comment.shellescape}" if comment
      command << "-f #{private_key_file.shellescape}"
      local_exec! command * ' ', "Failed to generate SSH key pair #{private_key_file}"
      File.chmod 0600, private_key_file
      true
    end

    def public_key
      File.read(public_key_file).strip
    end
  end
end
