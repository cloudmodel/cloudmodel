module CloudModel
  # A Solr configuration image built from a Git repository and deployed to
  # {Services::Solr} instances.
  #
  # The Git repository must contain:
  # - `SOLR_VERSION` — a text file with the required Solr version string
  # - `solr/` — a directory with the Solr core/collection configuration
  #
  # The build process clones the repo, reads `SOLR_VERSION`, packages the config,
  # and stores the result in MongoDB GridFS. On deployment, the tarball is
  # extracted onto the Solr container alongside the Solr binary from {SolrMirror}.
  class SolrImage
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::ENumFields
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] name
    #   @return [String] unique label for this Solr configuration
    field :name, type: String

    # @!attribute [rw] git_server
    #   @return [String] Git server hostname
    field :git_server, type: String

    # @!attribute [rw] git_repo
    #   @return [String] repository path on the Git server
    field :git_repo, type: String

    # @!attribute [rw] git_branch
    #   @return [String] branch to build from (default: `"master"`)
    field :git_branch, type: String, default: 'master'

    # @!attribute [rw] git_commit
    #   @return [String, nil] SHA of the last built commit
    field :git_commit, type: String

    # @!attribute [rw] solr_version
    #   @return [String, nil] Solr version read from the repo's `SOLR_VERSION` file
    field :solr_version, type: String

    enum_field :build_state, {
      0x00 => :pending,
      0x01 => :running,
      0x02 => :checking_out,
      0x05 => :packaging,
      0x06 => :storing,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    field :build_last_issue, type: String

    # @!attribute [rw] file
    #   @return [Mongoid::GridFS::Fs::File, nil] the packaged config tarball in GridFS
    belongs_to :file, class_name: "Mongoid::GridFS::Fs::File", optional: true

    validates :name, presence: true, uniqueness: true
    validates :git_server, presence: true
    validates :git_repo, presence: true
    validates :git_branch, presence: true

    used_in_guests_as 'services.deploy_solr_image_id'

    def services
      services = []
      used_in_guests.each do |guest|
        guest.services.where('deploy_solr_image_id': id).each do |service|
          services << service
        end
      end
      services
    end

    # @return [Integer, nil] size of the stored GridFS file in bytes
    def file_size
      file.try :length
    end

    # Finds the {SolrMirror} that matches this image's Solr version.
    # @return [CloudModel::SolrMirror, nil]
    def solr_mirror
      CloudModel::SolrMirror.find_by(version: solr_version)
    end

    # @return [String] local filesystem path used as a scratch directory during builds
    def build_path
      Pathname.new(CloudModel.config.data_directory).join('build', 'solr_images', id).to_s
    end

    def self.build_state_id_for build_state
      enum_fields[:build_state][:values].invert[build_state]
    end

    def self.buildable_build_states
      [:finished, :failed, :not_started]
    end

    def self.buildable_build_state_ids
      buildable_build_states.map{|s| build_state_id_for s}
    end

    def buildable?
      self.class.buildable_build_states.include? build_state
    end

    def self.buildable
      scoped.where :build_state_id.in => buildable_build_state_ids
    end

    def build(options = {})
      unless buildable? or options[:force]
        return false
      end

      update_attribute :build_state, :pending

      begin
        CloudModel::SolrImageJobs::BuildJob.perform_later id.to_s
      rescue Exception => e
        update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    def worker
      CloudModel::Workers::SolrImageWorker.new self
    end

    def build!(options = {})
      unless buildable? or options[:force]
        return false
      end

      self.build_state = :pending

      worker.build options
    end
  end
end
