module CloudModel
  class GuestCertificate
    include Mongoid::Document
    include Mongoid::Timestamps
    
    belongs_to :guest, class_name: "CloudModel::Guest"
    belongs_to :certificate, class_name: "CloudModel::Certificate"
    field :path_to_crt, type: String
    field :path_to_key, type: String
  end
end