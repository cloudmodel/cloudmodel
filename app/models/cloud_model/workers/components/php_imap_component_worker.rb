module CloudModel
  module Workers
    module Components
      # Component worker that installs the PHP IMAP extension into a guest template chroot.
      #
      # Installs `phpN-imap` where N is the configured PHP version.
      class PhpImapComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install php#{CloudModel.config.php_version}-imap -y", "Failed to install php imap module"
        end
      end
    end
  end
end