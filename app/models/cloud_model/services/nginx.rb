module CloudModel
  module Services
    class Nginx < Base
      include CloudModel::Mixins::ENumFields

      field :port, type: Integer, default: 80
      field :ssl_supported, type: Mongoid::Boolean#, default: false
      field :ssl_only, type: Mongoid::Boolean, default: false
      field :ssl_enforce, type: Mongoid::Boolean, default: false
      field :ssl_port, type: Integer, default: 443
      field :ssl_certbot, type: Mongoid::Boolean, default: false
      belongs_to :ssl_cert, class_name: 'CloudModel::Certificate', inverse_of: :services, optional: true

      field :passenger_supported, type: Mongoid::Boolean, default: false
      field :passenger_env, type: String, default: 'production'
      field :delayed_jobs_supported, type: Mongoid::Boolean, default: false

      field :fastcgi_supported, type: Mongoid::Boolean, default: false
      field :fastcgi_location, type: String, default: ".php$"
      field :fastcgi_pass, type: String, default: "127.0.0.1:9000"
      field :fastcgi_index, type: String, default: "index.php"

      field :capistrano_supported, type: Mongoid::Boolean, default: false

      belongs_to :deploy_web_image, class_name: 'CloudModel::WebImage', inverse_of: :services, optional: true

      enum_field :redeploy_web_image_state, {
        0x00 => :pending,
        0x01 => :running,
        0xf0 => :finished,
        0xf1 => :failed,
        0xff => :not_started
      }, default: :not_started

      field :redeploy_web_image_last_issue, type: String


      field :deploy_mongodb_host, type: String
      field :deploy_mongodb_port, type: Integer, default: 27017
      field :deploy_mongodb_database, type: String

      belongs_to :deploy_mongodb_replication_set, class_name: 'CloudModel::MongodbReplicationSet', optional: true

      field :deploy_redis_host, type: String
      field :deploy_redis_port, type: Integer, default: 6379

      belongs_to :deploy_redis_sentinel_set, class_name: 'CloudModel::RedisSentinelSet', optional: true

      field :daily_rake_task, type: String, default: nil

      def kind
        :http
      end

      def components_needed
        if passenger_supported or capistrano_supported
          components = [:ruby, :nginx]
          if deploy_web_image
            components += deploy_web_image.additional_components.map &:to_sym
          end
          (components + super).uniq
        else
          ([:nginx] + super).uniq
        end
      end

      def used_ports
        if ssl_supported?
          if ssl_only?
            [ssl_port]
          else
            [port, ssl_port]
          end
        else
          super
        end
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

        begin
          Net::HTTP.start(uri.host, uri.port,
            :use_ssl => ssl_supported,
            :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|

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
        CloudModel::Workers::Services::NginxWorker.new self.guest, self
      end

      def redeploy(options = {})
        unless redeployable? or options[:force]
          return false
        end

        update_attribute :redeploy_web_image_state, :pending

        begin
          CloudModel::call_rake 'cloudmodel:services:nginx:redeploy', guest_id: guest.id, service_id: id
        rescue Exception => e
          update_attributes redeploy_web_image_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
          CloudModel.log_exception e
        end
      end

      def redeploy!(options = {})
        unless redeployable? or options[:force]
          return false
        end

        worker.redeploy_web_image options
      end

    end
  end
end