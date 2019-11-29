module CloudModel
  module Services
    class Nginx < Base
      include CloudModel::ENumFields

      field :port, type: Integer, default: 80
      field :ssl_supported, type: Mongoid::Boolean#, default: false
      field :ssl_only, type: Mongoid::Boolean, default: false
      field :ssl_enforce, type: Mongoid::Boolean, default: false
      field :ssl_port, type: Integer, default: 443
      belongs_to :ssl_cert, class_name: 'CloudModel::Certificate', inverse_of: :services, optional: true
      
      field :passenger_supported, type: Mongoid::Boolean, default: false
      field :passenger_env, type: String, default: 'production'
      field :delayed_jobs_supported, type: Mongoid::Boolean, default: false
      
      field :capistrano_supported, type: Mongoid::Boolean, default: false
      
      belongs_to :deploy_web_image, class_name: 'CloudModel::WebImage', inverse_of: :services, optional: true
      
      enum_field :redeploy_web_image_state, values: {
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
    
      
      def www_home
        "/var/www"
      end
      
      def www_root
        "#{www_home}/rails"
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
      
      def kind
        :http
      end
      
      def self.redeployable_redeploy_web_image_states
        [:finished, :failed, :not_started]
      end    
    
      def redeployable?
        self.class.redeployable_redeploy_web_image_states.include? redeploy_web_image_state
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
        worker = CloudModel::Services::NginxWorker.new self.guest, self
        worker.redeploy_web_image options
      end
      
      def components_needed
        if passenger_supported or capistrano_supported
          [:ruby, :nginx]
        else
          [:nginx]
        end
      end
      
      def shinken_services_append
        services_string = ''
        unless ssl_only
          services_string += ', nginx'
        end
        
        if ssl_supported
          services_string += ', https'
        end
        
        services_string
      end
      
      def livestatus
        if guest.livestatus
          guest.livestatus.services.find{|s| s.description == 'Nginx'} || guest.livestatus.services.find{|s| s.description == 'HttpsCertificate'}
        end
      end
      
    end
  end
end