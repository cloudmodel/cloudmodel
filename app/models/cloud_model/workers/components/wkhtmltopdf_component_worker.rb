module CloudModel
  module Workers
    module Components
      class WkhtmltopdfComponentWorker < BaseComponentWorker
        def build build_path
          # Ruby deps needed for most rails projects
          # TODO: Consider separating them to more Components
          packages = %w(wkhtmltopdf)
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for wkhtmltopdf"
        end
      end
    end
  end
end