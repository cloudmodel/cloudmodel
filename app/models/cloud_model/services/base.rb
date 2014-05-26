module CloudModel
  module Services
    class Base
      include Mongoid::Document
      include Mongoid::Timestamps
      include CloudModel::BackupTools
  
      field :name, type: String    
      field :public_service, type: Mongoid::Boolean, default: false
      field :has_backups, type: Mongoid::Boolean, default: false
   
      embedded_in :guest, class_name: "CloudModel::Guest", inverse_of: :services
  
      def self.service_types 
        {
          mongodb: 'CloudModel::Services::Mongodb',
          nginx: 'CloudModel::Services::Nginx',
          redis: 'CloudModel::Services::Redis',
          ssh: 'CloudModel::Services::Ssh',
          tomcat: 'CloudModel::Services::Tomcat'
        }
      end
    
      def used_ports
        [port]
      end
    
      def kind
        :unknown
      end
      
      def backupable?
        false
      end
      
      def has_backups=(state)
        self[:has_backups] = state && backupable?
      end
      
      def backup_directory
        "#{CloudModel.config.backup_directory}/#{guest.host.id}/#{guest._id}/services/#{_id}"
      end
      
      def backup
        raise "Service has no backups"
      end
      
      def restore timestamp='latest'
        raise "Service has no restore"
      end
    end
  end
end
