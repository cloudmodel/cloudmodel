module CloudModel
  module Workers
    module Components
      class PhpImapComponentWorker < BaseComponentWorker
        def build build_path
          chroot! build_path, "apt-get install php#{CloudModel.config.php_version}-imap -y", "Failed to install php imap module"
        end
      end
    end
  end
end