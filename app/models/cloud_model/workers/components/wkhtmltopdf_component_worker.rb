module CloudModel
  module Workers
    module Components
      class WkhtmltopdfComponentWorker < BaseComponentWorker
        def build build_path
          # Dependencies
          packages = %w( xfonts-75dpi xfonts-base fontconfig libjpeg-turbo8 libxrender1 )
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for wkhtmltopdf dependencies"

          uri = URI.parse('https://wkhtmltopdf.org/downloads.html')
          page_content = uri.read
          package_uri = page_content.scan(/href="([^"]*#{CloudModel.config.ubuntu_short_name}_#{@host.arch}[^"]*)"/).first.first
          package_name = package_uri.split('/').last

          chroot! build_path, "wget -q #{package_uri} && dpkg -i #{package_name} && apt -f install", "Failed to install packages for wkhtmltopdf"
        end
      end
    end
  end
end