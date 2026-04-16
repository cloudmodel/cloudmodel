module CloudModel
  module Workers
    module Components
      # Component worker that installs libxml2 and libxslt into a guest template chroot.
      #
      # Installs `libxml2-dev`, `libxml2-utils`, `libxslt-dev`, and `xsltproc`.
      class XmlComponentWorker < BaseComponentWorker
        def build build_path
          packages = %w(libxml2-dev libxml2-utils libxslt-dev xsltproc)
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for libxml"
        end
      end
    end
  end
end