module CloudModel
  module Workers
    module Components
      class XmlComponentWorker < BaseComponentWorker
        def build build_path
          # Ruby deps needed for most rails projects
          # TODO: Consider separating them to more Components
          packages = %w(libxml2-dev libxml2-utils libxslt-dev)
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for libxml"
        end
      end
    end
  end
end