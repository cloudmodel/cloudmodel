module CloudModel
  module Services
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

      # Content Security Policies
      field :unsafe_inline_script_allowed, type: Mongoid::Boolean, default: false
      field :unsafe_eval_script_allowed, type: Mongoid::Boolean, default: false
      field :google_analytics_supported, type: Mongoid::Boolean, default: false
      field :hubspot_forms_supported, type: Mongoid::Boolean, default: false
      field :pingdom_supported, type: Mongoid::Boolean, default: false

      # Support reverse proxy
      field :reverse_proxy_supported, type: Mongoid::Boolean, default: false
      field :reverse_proxy_for, type: String, default: nil

      # Passenger support
      field :passenger_supported, type: Mongoid::Boolean, default: false
      field :passenger_env, type: String, default: 'production'
      field :passenger_ruby_version, type: String, default: CloudModel.config.ruby_version
      field :delayed_jobs_supported, type: Mongoid::Boolean, default: false
      field :delayed_jobs_queues, type: Array, default: ['default']

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

      def components_needed
        components = [:nginx]

        web_locations.each do |loc|
          components = loc.web_app.needed_components + components
        end

        if passenger_supported or capistrano_supported
          components = [:"ruby@#{passenger_ruby_version}"] + components
          if deploy_web_image
            components += deploy_web_image.additional_components.map &:to_sym
          end
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

      def redeploy(options = {})
        unless redeployable? or options[:force]
          return false
        end

        update_attribute :redeploy_web_image_state, :pending

        begin
          CloudModel::Services::NginxJobs::RedeployJob.perform_later id.to_s, guest.id.to_s
        rescue Exception => e
          update_attributes redeploy_web_image_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
          CloudModel.log_exception e
        end
      end

      def redeploy!(options = {})
        unless redeployable? or redeploy_web_image_state == :pending or options[:force]
          return false
        end

        worker.redeploy_web_image options
      end

    end
  end
end