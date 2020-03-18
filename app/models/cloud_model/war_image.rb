module CloudModel  
  class WarImage
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::UsedInGuestsAs
    prepend CloudModel::SmartToString
   
    field :name, type: String
    belongs_to :file, class_name: "Mongoid::GridFS::Fs::File"

    validates :name, presence: true, uniqueness: true
    validates :file, presence: true
    
    used_in_guests_as 'services.deploy_war_image_id'
    
    def file_size
      file.try :length
    end
    
    def file_upload=(uploaded_file)
      file = Mongoid::GridFs.put(uploaded_file.tempfile.path)
      self.file_id = file.id
    end
  end
end