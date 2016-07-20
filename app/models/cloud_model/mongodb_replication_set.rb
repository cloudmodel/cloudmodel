module CloudModel
  class MongodbReplicationSet
    include Mongoid::Document
    include Mongoid::Timestamps
    
    field :name, type: String

    def services
      CloudModel::Guest.where("services.mongodb_replication_set_id" => id).map{ |guest| 
        guest.services.where("mongodb_replication_set_id" => id).to_a
      }.flatten   
    end
    
    def add_service service
      service.update_attributes mongodb_replication_set_id: id
    end
  end
end