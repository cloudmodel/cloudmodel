module CloudModel
  module Workers
    module Components
      # Component worker that installs wkhtmltopdf into a guest template chroot.
      #
      # Installs X font and rendering dependencies, then scrapes the wkhtmltopdf
      # downloads page to find the correct `.deb` package for the template's OS
      # version and host architecture, downloads it, and installs it with
      # `dpkg -i && apt -f install`.
      class WkhtmltopdfComponentWorker < BaseComponentWorker
        def build build_path
          # Dependencies
          packages = %w( xfonts-75dpi xfonts-base fontconfig libjpeg-turbo8 libxrender1 )
          chroot! build_path, "apt-get install #{packages * ' '} -y", "Failed to install packages for wkhtmltopdf dependencies"

          uri = URI.parse('https://wkhtmltopdf.org/downloads.html')
          page_content = uri.read
          package_uri = page_content.scan(/href="([^"]*#{CloudModel.debian_short_name(@template.os_version)}_#{@host.arch}[^"]*)"/).first.first
          package_name = package_uri.split('/').last

          chroot! build_path, "wget -q #{package_uri} && dpkg -i #{package_name} && apt -f install", "Failed to install packages for wkhtmltopdf"
        end
      end
    end
  end
end