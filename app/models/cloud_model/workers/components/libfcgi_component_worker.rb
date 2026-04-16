module CloudModel
  module Workers
    module Components
      # Component worker that installs the libFCGI shared library into a guest template chroot.
      #
      # Installs `libfcgi0ldbl`.
      class LibfcgiComponentWorker < BaseComponentWorker
        def build build_path
          # On mac for testing: brew install fcgi
          chroot! build_path, "apt-get install libfcgi0ldbl -y", "Failed to install libfcgi"
        end
      end
    end
  end
end