module CloudModel
  # A Java WAR file uploaded to MongoDB GridFS and deployed to Tomcat guests.
  #
  # Services of type {Services::Tomcat} reference a WarImage via
  # `deploy_war_image_id`. The WAR file is stored in GridFS and transferred to
  # the container's Tomcat webapps directory during deployment.
  class WarImage
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString
   
    # @!attribute [rw] name
    #   @return [String] unique label for this WAR image (used as the Tomcat context path)
    field :name, type: String

    # @!attribute [rw] file
    #   @return [Mongoid::GridFS::Fs::File] the uploaded WAR file stored in GridFS
    belongs_to :file, class_name: "Mongoid::GridFS::Fs::File"

    validates :name, presence: true, uniqueness: true
    validates :file, presence: true

    used_in_guests_as 'services.deploy_war_image_id'

    # @return [Integer, nil] size of the WAR file in bytes
    def file_size
      file.try :length
    end

    # Receives a Rack-compatible uploaded file object, stores it in GridFS, and
    # sets {#file_id}.
    # @param uploaded_file [ActionDispatch::Http::UploadedFile]
    def file_upload=(uploaded_file)
      file = Mongoid::GridFs.put(uploaded_file.tempfile.path)
      self.file_id = file.id
    end
  end
end