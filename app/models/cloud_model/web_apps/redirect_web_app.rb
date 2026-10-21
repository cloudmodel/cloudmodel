module CloudModel
  module WebApps
    # Web application that only redirects: every request below its web
    # location is answered with a redirect to another site, the request path
    # and query string appended. A stand-in for a site that moved (domain
    # change, a blog folded into the main site) that needs no application
    # stack on the guest at all — nginx answers from its configuration.
    #
    # Optional path handling for sites whose structure changed on the move:
    # `normalize_html` turns `/dir/index.html` into `/dir/` and `/page.html`
    # into `/page/` before the path is looked up, and `path_mapping` sends
    # single old paths to new ones. Either option renders nginx `map` blocks
    # (http context, `conf.d`) next to the location block.
    class RedirectWebApp < ::CloudModel::WebApp
      STATUS_CODES = [301, 302, 307, 308].freeze

      # The rendered values go into nginx directives verbatim, so the
      # characters that would end or alter a directive are refused.
      URL_FORMAT = %r{\Ahttps?://[A-Za-z0-9.\-]+(:\d+)?(/[^\s"'`{}$;\\]*)?\z}
      PATH_FORMAT = %r{\A/[^\s"'`{}$;\\]*\z}

      # @!attribute [rw] target_url
      #   @return [String] base URL of the site redirected to; the request's
      #     path and query string are appended
      field :target_url, type: String

      # @!attribute [rw] root_url
      #   @return [String] URL for the location itself (`/`) when the front
      #     page moved elsewhere than the rest; blank follows `target_url`
      field :root_url, type: String, default: ''

      # @!attribute [rw] status
      #   @return [Integer] HTTP status of the redirect (default: 301)
      field :status, type: Integer, default: 301

      # @!attribute [rw] normalize_html
      #   @return [Boolean] strip `index.html` and turn `.html` pages into
      #     directories before the path mapping (default: false)
      field :normalize_html, type: Mongoid::Boolean, default: false

      # @!attribute [rw] path_mapping
      #   @return [Array<Array(String, String)>] `[old path, new path]` pairs
      #     (new paths relative to `target_url`); paths not listed keep their
      #     own. Pairs rather than a Hash: paths carry dots, which MongoDB
      #     keys can't.
      field :path_mapping, type: Array, default: []

      validates :target_url, presence: true, format: { with: URL_FORMAT }
      validates :root_url, format: { with: URL_FORMAT }, allow_blank: true
      validates :status, inclusion: { in: STATUS_CODES }
      validate :path_mapping_paths

      def additional_allowed_params
        [:target_url, :root_url, :status, :normalize_html, :path_mapping_text]
      end

      # The path mapping as text for forms: one `old new` pair per line.
      # @return [String]
      def path_mapping_text
        path_mapping.map { |from, to| "#{from} #{to}" } * "\n"
      end

      # Parses the one-pair-per-line form of {#path_mapping}; blank lines
      # and `#` comments are skipped, a line without a second word becomes
      # an invalid pair so validation reports it.
      # @param text [String]
      def path_mapping_text= text
        self.path_mapping = text.to_s.lines.filter_map do |line|
          line = line.strip
          next if line.blank? or line.start_with?('#')
          from, to = line.split(/\s+/, 2)
          [from, to.to_s]
        end
      end

      # Whether the redirect needs nginx `map` blocks (any path handling).
      # @return [Boolean]
      def needs_map?
        normalize_html? or path_mapping.present?
      end

      # nginx variable the map blocks set to the redirect's path, unique per
      # app so two redirect apps can share one guest.
      # @return [String] e.g. `"$redirect_65d7…_path"`
      def map_variable
        "$redirect_#{id}_path"
      end

      # Intermediate variable of the normalization map.
      # @return [String]
      def normalized_variable
        "$redirect_#{id}_normalized"
      end

      # Prefix for the named captures of the normalization map (a capture
      # name is a variable, so it has to be unique per app as well).
      # @return [String]
      def capture_prefix
        "redirect_#{id}"
      end

      # `target_url` without a trailing slash, since the request path that
      # is appended starts with one.
      # @return [String]
      def target_base
        target_url.to_s.sub(%r{/+\z}, '')
      end

      # The nginx expression for the redirect's location: the mapped path
      # with the original query string, or the raw request URI when no path
      # handling is configured.
      # @return [String]
      def target_expression
        if needs_map?
          "#{target_base}#{map_variable}$is_args$args"
        else
          "#{target_base}$request_uri"
        end
      end

      # The map blocks go to the http context; the location block is rendered
      # by the nginx worker from the app's `nginx.conf` template.
      def config_files_to_render
        return {} unless needs_map?

        {
          'cloud_model/web_apps/redirect_web_app/map.conf' => ["/etc/nginx/conf.d/redirect-#{file_slug}.conf", 0644]
        }
      end

      # @return [String] file-name-safe form of the app name
      def file_slug
        name.to_s.underscore.gsub(/[^a-z0-9_]+/, '_')
      end

      private

      # Reported on the form attribute so the field in the edit form shows it.
      def path_mapping_paths
        path_mapping.each do |from, to|
          unless from.to_s =~ PATH_FORMAT and to.to_s =~ PATH_FORMAT
            errors.add :path_mapping_text, :invalid, value: "#{from} #{to}".strip
          end
        end
      end
    end
  end
end
