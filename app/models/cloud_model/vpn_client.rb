module CloudModel
  class VpnClient
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString
 
    field :name, type: String
    field :tinc_public_key, type: String
    field :address, type: String
    
    validates :name, presence: true, uniqueness: true, format: {with: /\A[a-z0-9\-_]+\z/}
    validates :tinc_public_key, presence: true
    validates :address, presence: true, format: /\A((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)(\.)){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/
  end
end