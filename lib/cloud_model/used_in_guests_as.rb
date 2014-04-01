module CloudModel
  module UsedInGuestsAs
    def self.included(base)
      base.extend ClassMethods
    end
    
    def used_in_guests
      CloudModel::Guest.where(self.class.cloud_model_used_in_guests_field => id)
    end
    
    def used_in_guests_by_hosts
      guests_by_hosts = {}
      
      used_in_guests.each do |guest|
        guests_by_hosts[guest.host_id] ||= []
        guests_by_hosts[guest.host_id] << guest
      end
      
      guests_by_hosts
    end
        
    module ClassMethods   
      def used_in_guests_as field
        @cloud_model_used_in_guests_field = field
      end
      
      def cloud_model_used_in_guests_field
        @cloud_model_used_in_guests_field 
      end
    end
  end
end