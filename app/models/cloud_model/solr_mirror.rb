module CloudModel
  class SolrMirror
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::ModelHasIssues
    prepend CloudModel::SmartToString
        
    field :version, type: String

    has_many :solr_images, class_name: "CloudModel::SolrImage"
    belongs_to :file, class_name: "Mongoid::GridFS::Fs::File", optional: true
    
    validates :version, presence: true, uniqueness: true
    
    after_create :update_file
    
    def original_file_url
      "http://archive.apache.org/dist/lucene/solr/#{version}/solr-#{version}.tgz"  
    end
    
    def local_filename
      "solr-#{version}.tgz"
    end
    
    def update_file
      old_gridfs_file = file
      tempfile = Tempfile.new(local_filename)
      tempfile.binmode
      
      uri = URI.parse(original_file_url)
      Net::HTTP.start(uri.host,uri.port) do |http| 
        http.request_get(uri.path) do |res| 
          res.read_body do |part|
            tempfile << part
            # Avoid pulling to hard on http to reduce CPU load
            sleep 0.005 
          end
        end
      end
        
      gridfs_file = Mongoid::GridFs.put(tempfile.path)
      gridfs_file.update_attribute :filename, local_filename
      self.update_attribute :file_id, gridfs_file.id
      tempfile.close
      old_gridfs_file.destroy if old_gridfs_file
    end
    
    def file_size
      file.try :length
    end
  end
end
  