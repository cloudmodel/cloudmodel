module CloudModel
  module Workers
    module Components
      class PhpComponentWorker < BaseComponentWorker
        def build build_path
          packages = %w(php-fpm)
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for deployment of php app"
        end
      end
    end
  end
end