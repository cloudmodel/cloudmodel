module CloudModel
  # A locally cached copy of a Solr release tarball stored in MongoDB GridFS.
  #
  # SolrMirror records are created with the desired Solr version. On creation,
  # {#update_file} is triggered automatically to download the tarball from the
  # Apache archive and store it in GridFS. {SolrImage} records reference a
  # SolrMirror via {#solr_version} so the correct binary can be deployed
  # alongside the configuration.
  class SolrMirror
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] version
    #   @return [String] Solr version string, e.g. `"9.5.0"`
    field :version, type: String

    # @!attribute [r] solr_images
    #   @return [Array<CloudModel::SolrImage>] images that use this Solr version
    has_many :solr_images, class_name: "CloudModel::SolrImage"

    # @!attribute [rw] file
    #   @return [Mongoid::GridFS::Fs::File, nil] the downloaded tarball in GridFS
    belongs_to :file, class_name: "Mongoid::GridFS::Fs::File", optional: true

    validates :version, presence: true, uniqueness: true

    after_create :update_file

    # Returns the Apache archive URL for downloading this Solr release.
    # Solr 9+ moved from `lucene/solr` to `solr/solr` in the archive path.
    # @return [String]
    def original_file_url
      if version.to_i >= 9
        source = "http://archive.apache.org/dist/solr/solr/#{version}/solr-#{version}.tgz"
      else
        source = "http://archive.apache.org/dist/lucene/solr/#{version}/solr-#{version}.tgz"
      end
    end

    # @return [String] the filename used when storing in GridFS, e.g. `"solr-9.5.0.tgz"`
    def local_filename
      "solr-#{version}.tgz"
    end

    # Downloads the Solr tarball from the Apache archive, saves it to GridFS,
    # and removes any previously stored file. Called automatically after create.
    def update_file
      old_gridfs_file = file
      tempfile = Tempfile.new(local_filename)
      tempfile.binmode

      `curl -o #{tempfile.path.shellescape} #{original_file_url.shellescape}`

      # uri = URI.parse(original_file_url)
      # Net::HTTP.start(uri.host,uri.port) do |http|
      #   http.request_get(uri.path) do |res|
      #     unless res.is_a? Net::HTTPOK
      #       raise 'Solr source not found'
      #     end
      #
      #     res.read_body do |part|
      #       tempfile << part
      #       print '#'
      #       # Avoid pulling to hard on http to reduce CPU load
      #       #sleep 0.005
      #     end
      #   end
      # end

      gridfs_file = Mongoid::GridFs.put(tempfile.path)
      gridfs_file.update_attribute :filename, local_filename
      self.update_attribute :file_id, gridfs_file.id
      tempfile.close
      old_gridfs_file.destroy if old_gridfs_file
    end

    # @return [Integer, nil] size of the stored GridFS file in bytes
    def file_size
      file.try :length
    end
  end
end
