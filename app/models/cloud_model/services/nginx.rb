module CloudModel
  module Services
    # Nginx web server / reverse proxy service embedded in a {Guest}.
    #
    # Nginx is the primary public-facing service. It supports:
    # - Static file serving and reverse proxying
    # - TLS termination (manual certificate or Certbot)
    # - Phusion Passenger (for Rails/Ruby apps)
    # - Capistrano deployments
    # - {WebImage} deployment (Rails apps packaged as GridFS tarballs)
    # - {WebLocation}s that mount {WebApp} subclasses at URL path prefixes
    # - Content Security Policy generation
    #
    # The `redeploy_web_image_state` tracks rolling out a new {WebImage} build
    # independently of the guest's `deploy_state`.
    class Nginx < Base
      include CloudModel::Mixins::ENumFields

      field :port, type: Integer, default: 80

      embeds_many :location_overwrites, class_name: CloudModel::Services::Nginx::LocationOverwrite, inverse_of: :service
      accepts_nested_attributes_for :location_overwrites, allow_destroy: true

      # SSL/TLS settings
      field :ssl_supported, type: Mongoid::Boolean#, default: false
      field :ssl_only, type: Mongoid::Boolean, default: false
      field :ssl_enforce, type: Mongoid::Boolean, default: false
      field :ssl_port, type: Integer, default: 443
      field :ssl_certbot, type: Mongoid::Boolean, default: false
      belongs_to :ssl_cert, class_name: CloudModel::Certificate, inverse_of: :services, optional: true
      # With Let's Encrypt the cert is certbot's business: no preselected
      # certificate — the deploy bootstraps a self-signed one so nginx comes
      # up at all (no ssl listener without cert files, no running nginx no
      # ACME challenge) and certbot replaces it on first start.
      before_validation :clear_ssl_cert_for_certbot
      validates :ssl_cert, presence: true, if: -> { ssl_supported? && !ssl_certbot? }

      # Content Security Policies
      field :unsafe_inline_script_allowed, type: Mongoid::Boolean, default: false
      field :unsafe_eval_script_allowed, type: Mongoid::Boolean, default: false
      field :google_analytics_supported, type: Mongoid::Boolean, default: false
      field :hubspot_forms_supported, type: Mongoid::Boolean, default: false
      field :pingdom_supported, type: Mongoid::Boolean, default: false

      # Support reverse proxy
      field :reverse_proxy_supported, type: Mongoid::Boolean, default: false
      field :reverse_proxy_for, type: String, default: nil

      # Attribute changes fully covered by the rendered nginx config files —
      # NginxWorker#sync_config can push them to the running guest without a
      # redeploy. Everything else (ports/firewall, SSL certs, systemd units,
      # web image, dependencies, web locations, …) only takes effect on the
      # next deploy. Changes to embedded location_overwrites are live-syncable
      # too; embedded web_locations are not (their app confs render at deploy).
      LIVE_SYNCABLE_ATTRIBUTES = %w(
        ssl_only ssl_enforce
        unsafe_inline_script_allowed unsafe_eval_script_allowed
        google_analytics_supported hubspot_forms_supported pingdom_supported
        reverse_proxy_for passenger_env rails_cable_supported
      ).freeze

      # Passenger support
      field :passenger_supported, type: Mongoid::Boolean, default: false
      field :passenger_env, type: String, default: 'production'
      field :passenger_ruby_version, type: String, default: CloudModel.config.ruby_version
      field :delayed_jobs_supported, type: Mongoid::Boolean, default: false
      field :delayed_jobs_queues, type: Array, default: ['default']
      # Serve /cable (Rails ActionCable WebSocket) in a dedicated Passenger app
      # group with unlimited request concurrency, so open sockets don't pin
      # regular app processes.
      field :rails_cable_supported, type: Mongoid::Boolean, default: false

      # Deploy via capistrano
      field :capistrano_supported, type: Mongoid::Boolean, default: false
      has_and_belongs_to_many :capistrano_ssh_groups, class_name: CloudModel::SshGroup, inverse_of: :services

      # WebLocation support
      embeds_many :web_locations, class_name: CloudModel::WebLocation, inverse_of: :service
      accepts_nested_attributes_for :web_locations, allow_destroy: true

      # WebImage support
      belongs_to :deploy_web_image, class_name: CloudModel::WebImage, inverse_of: :services, optional: true
      enum_field :redeploy_web_image_state, {
        0x00 => :pending,
        0x01 => :running,
        0xf0 => :finished,
        0xf1 => :failed,
        0xff => :not_started
      }, default: :not_started
      field :redeploy_web_image_last_issue, type: String

      # Current step of a running web image rollout on this service
      # (unroll/transfer/permissions/activate/restart/done) — drives the
      # per-instance progress bar on the WebImage page.
      field :redeploy_web_image_step, type: String

      # MongoDB config for web image
      field :deploy_mongodb_host, type: String
      field :deploy_mongodb_port, type: Integer, default: 27017
      field :deploy_mongodb_database, type: String
      field :deploy_mongodb_write_concern, type: String, default: 'majority'
      field :deploy_mongodb_read_preference, type: String, default: 'primary'
      validates :deploy_mongodb_read_preference, inclusion: {in: :allowed_deploy_mongodb_read_preferences}
      belongs_to :deploy_mongodb_replication_set, class_name: '::CloudModel::MongodbReplicationSet', optional: true

      # Redis config for web image
      field :deploy_redis_host, type: String
      field :deploy_redis_port, type: Integer, default: 6379
      belongs_to :deploy_redis_sentinel_set, class_name: '::CloudModel::RedisSentinelSet', optional: true


      def kind
        :http
      end

      # Nginx is the primary public-facing web server / reverse proxy.
      def allow_public_service?
        true
      end

      def components_needed
        components = [:nginx]

        web_locations.each do |loc|
          components = loc.web_app.needed_components + components
        end

        if passenger_supported or capistrano_supported
          # The deployed web image's ruby_version is the source of truth — the
          # runtime Ruby that Passenger boots must match the one the artifact was
          # built against. Fall back to passenger_ruby_version when unset.
          ruby = deploy_web_image&.ruby_version.presence || passenger_ruby_version
          components = [:"ruby@#{ruby}"] + components
          # NOTE: deploy_web_image.additional_components (e.g. :rust) are
          # build-env-only toolchain — they go into WebImage#build_env_template,
          # NOT the runtime guest template, which stays lean (only the compiled
          # native extensions run here, never cargo/rustc).
          (components + super).uniq
        else
          (components + super).uniq
        end
      end

      def used_ports
        if ssl_supported?
          if ssl_only?
            [[ssl_port, :tcp]]
          else
            [[port, :tcp], [ssl_port, :tcp]]
          end
        else
          super
        end
      end

      def delayed_jobs_queues=(queues)
        if queues.is_a? String
          queues = queues.split(' ')
        end

        super queues
      end

      def external_uri
        "http#{ssl_supported ? 's' : ''}://#{guest.private_address}:#{ssl_supported ? ssl_port : port}/"
      end

      def internal_uri
        "http#{ssl_supported ? 's' : ''}://#{guest.private_address}:#{ssl_supported ? ssl_port : port}/"
      end

      def status_uri
        "#{internal_uri}/nginx_status"
      end

      def service_status
        data = {}
        uri = URI(status_uri)
        res = nil
        cert = nil

        begin
          Net::HTTP.start(uri.host, uri.port,
            :use_ssl => ssl_supported,
            :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

            if ssl_supported
              cert = http.peer_cert
            end

            req = Net::HTTP::Get.new uri.request_uri
            res = http.request req
          end
        rescue Exception => e
          return {key: :not_reachable, error: "#{e.class}\n\n#{e.to_s}", severity: :critical}
        end

        begin
          data['http_version'] = res.http_version
          data['active'] = res.body.lines[0].gsub('Active connections: ', '').to_i
          data['accepted'], data['handled'], data['requests'] = res.body.lines[2].strip.split(' ').map(&:to_i)

          res.body.lines[3].gsub(/\W*:\W*/, ':').split(' ').each do |pair|
            k,v = pair.split ':'
            data["#{k.downcase}"] = v
          end
        rescue Exception => e
           return {key: :parse_nginx_result, error: "#{e.class}\n\n#{e.to_s}", severity: :warning}
        end

        begin
          if ssl_supported
            data['ssl_cert'] = {
              'not_before' => cert.not_before,
              'not_after' => cert.not_after,
              'issuer' => cert.issuer.to_a.map{|v| [v[0],v[1]]}.to_h,
              'subject' => cert.subject.to_a.map{|v| [v[0],v[1]]}.to_h
            }
          end
        rescue
          return {key: :parse_ssl_cert, error: "#{e.class}\n\n#{e.to_s}", severity: :warning}
        end

        if res.code == '404'
          return {key: :no_nginx_status, error: "404: nginx_status not found on server, but server running", severity: :warning}
        end
        if res.code == '403'
          return {key: :ngnix_status_forbidden, error: "403: no privileges to access nginx_status on server", severity: :warning}
        end

        if passenger_supported
          success, passenger_data = guest.exec('passenger-status --show xml')

          if success
            data['passenger'] = Hash.from_xml(passenger_data)['info']

            begin
              if data['passenger']['supergroups'] and data['passenger']['supergroups']['supergroup']
                supergroups = data['passenger']['supergroups']['supergroup']
                supergroups = [supergroups] unless supergroups.is_a? Array

                supergroups.each do |supergroup|
                  if supergroup['group'] and supergroup['group']['processes']
                    processes = supergroup['group']['processes']['process']
                    processes = [processes] unless processes.is_a? Array
                    supergroup['group']['processes'] = processes
                  end
                end

                data['passenger']['supergroups'] = supergroups
              end
            rescue => e
              return {key: :parse_passenger_result, error: "#{e.class}\n\n#{e.to_s}", severity: :warning}
            end
          else
            return {key: :no_passenger_status, error: "passenger_status not found on server", severity: :warning}
          end

        end

        data
      end

      def allowed_deploy_mongodb_read_preferences
        ['nearest', 'primary', 'primary_preferred', 'secondary', 'secondary_preferred']
      end

      def www_home
        "/var/www"
      end

      def www_root
        "#{www_home}/rails"
      end

      def self.redeployable_redeploy_web_image_states
        [:finished, :failed, :not_started]
      end

      def redeployable?
        self.class.redeployable_redeploy_web_image_states.include? redeploy_web_image_state
      end

      def worker
        CloudModel::Workers::Services::NginxWorker.new self.guest.current_lxd_container, self
      end

      def content_security_policy
        policies = {'script-src' => ["'self'"]}

        if google_analytics_supported?
          policies['script-src'] += %w(https://www.google-analytics.com https://ssl.google-analytics.com)
        end

        if hubspot_forms_supported?
          policies['script-src'] += %w(https://js.hsforms.net https://forms.hsforms.com https://www.google.com https://www.gstatic.com)
        end

        if pingdom_supported?
          policies['script-src'] << "https://rum-static.pingdom.net"
        end

        if unsafe_inline_script_allowed?
          policies['script-src'] << "'unsafe-inline'"
        end

        if unsafe_eval_script_allowed?
          policies['script-src'] << "'unsafe-eval'"
        end

        "#{policies.map{|k,v| "#{k} #{v.uniq * ' '}"} * ';'};"
      end

      def update_crt(options = {})
        if ssl_supported? and not ssl_certbot?
          puts "  - Updating nginx '#{name}' cert #{ssl_cert.name} on guest #{guest.name}" if options[:debug]
          guest.host.exec!("echo '#{ssl_cert.crt}' | lxc file push - #{guest.current_lxd_container.name}/etc/nginx/ssl/#{guest.external_hostname}.crt", "Failed to copy crt")
          guest.host.exec!("lxc exec #{guest.current_lxd_container.name} -- systemctl reload nginx", "Failed to reload nginx")
        end
      end

      def clear_ssl_cert_for_certbot
        self.ssl_cert_id = nil if ssl_certbot?
      end

      def redeploy!(options = {})
        unless redeployable? or redeploy_web_image_state == :pending or options[:force]
          return false
        end

        # Per-instance console: the rollout details land on this nginx
        # service, while the web image build_log keeps its summary lines.
        # Nested captures propagate outward via StdoutTee.
        with_live_log verbose: options[:verbose] do
          worker.redeploy_web_image options
        end
      end

    end
  end
end