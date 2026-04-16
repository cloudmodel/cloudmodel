module CloudModel
  module Mixins
    # Adds a `used_in_guests` query method to models that are referenced by
    # embedded service fields.
    #
    # Call `used_in_guests_as 'services.deploy_web_image_id'` in the class body
    # to register the dot-notated MongoDB field path. The generated
    # {#used_in_guests} method then queries {Guest} records that reference this
    # document at that path.
    #
    # @example
    #   class WebImage
    #     include CloudModel::Mixins::UsedInGuestsAs
    #     used_in_guests_as 'services.deploy_web_image_id'
    #   end
    #
    #   image.used_in_guests   # => Mongoid::Criteria<Guest>
    module UsedInGuestsAs
      def self.included(base)
        base.extend ClassMethods
      end

      # Returns all guests that reference this record at the registered field path.
      # @return [Mongoid::Criteria<CloudModel::Guest>]
      def used_in_guests
        CloudModel::Guest.where(self.class.cloud_model_used_in_guests_field => id)
      end

      # Returns guests grouped by their host ID.
      # @return [Hash{BSON::ObjectId => Array<CloudModel::Guest>}]
      def used_in_guests_by_hosts
        guests_by_hosts = {}
      
        used_in_guests.each do |guest|
          guests_by_hosts[guest.host_id] ||= []
          guests_by_hosts[guest.host_id] << guest
        end
      
        guests_by_hosts
      end
        
      module ClassMethods
        # Registers the dot-notated MongoDB field path used by {#used_in_guests}.
        # @param field [String] e.g. `'services.deploy_web_image_id'`
        def used_in_guests_as field
          @cloud_model_used_in_guests_field = field
        end

        # Returns the registered field path.
        # @return [String]
        def cloud_model_used_in_guests_field
          @cloud_model_used_in_guests_field
        end
      end
    end
  end
end