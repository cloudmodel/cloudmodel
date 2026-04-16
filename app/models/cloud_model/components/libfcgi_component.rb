module CloudModel
  module Components
    # Component that installs the libfcgi library into a guest template.
    #
    # Required by the PHP-FPM service for FastCGI support.
    class LibfcgiComponent < BaseComponent
      # @return [String] e.g. `"libFCGI 2.4.2"`
      def human_name
        "libFCGI #{version}".strip
      end
    end
  end
end