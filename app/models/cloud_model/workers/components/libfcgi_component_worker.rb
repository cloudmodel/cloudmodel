module CloudModel
  module Workers
    module Components
      class LibfcgiComponentWorker < BaseComponentWorker
        def build build_path
          # On mac for testing: brew install fcgi
          chroot! build_path, "apt-get install libfcgi0ldbl -y", "Failed to install libfcgi"
        end
      end
    end
  end
end