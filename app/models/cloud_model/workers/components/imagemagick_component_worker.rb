module CloudModel
  module Workers
    module Components
      class ImagemagickComponentWorker < BaseComponentWorker
        def build build_path
          packages = %w(imagemagick)
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for imagemagick"
        end
      end
    end
  end
end