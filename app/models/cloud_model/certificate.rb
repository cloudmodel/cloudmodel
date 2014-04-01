module CloudModel
  class Certificate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::UsedInGuestsAs
    
    field :name, type: String
    field :ca, type: String
    field :key, type: String
    field :crt, type: String
    field :valid_thru, type: Date
    
    #has_many :services
    
    used_in_guests_as 'services.ssl_cert_id'
    
    scope :valid, -> { where(:valid_thru.gt => Time.now) }
    
    def to_s
      name
    end
  end
end