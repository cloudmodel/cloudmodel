module CloudModel
  # A deployable Rails/Ruby web application image built from a Git repository.
  #
  # The build process clones the repository, runs `bundle install`, optionally
  # compiles assets, packages the result into a tarball, and stores it in
  # MongoDB GridFS. The tarball is then deployed to all Nginx services that
  # reference this image via `deploy_web_image_id`.
  #
  # Two separate state machines are tracked: {#build_state} for the packaging
  # step and {#redeploy_state} for rolling the new image out to guests.
  class WebImage
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::ENumFields
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] name
    #   @return [String] unique human-readable label
    field :name, type: String

    # @!attribute [rw] git_server
    #   @return [String] hostname or IP of the Git server
    field :git_server, type: String

    # @!attribute [rw] git_repo
    #   @return [String] repository path on the Git server
    field :git_repo, type: String

    # @!attribute [rw] git_branch
    #   @return [String] branch to build from (default: `"master"`)
    field :git_branch, type: String, default: 'master'

    # @!attribute [rw] git_commit
    #   @return [String, nil] SHA of the last built commit (set after a successful build)
    field :git_commit, type: String

    # @!attribute [rw] has_assets
    #   @return [Boolean] whether to run the Rails asset pipeline during build
    field :has_assets, type: Mongoid::Boolean, default: false

    # @!attribute [rw] has_mongodb
    #   @return [Boolean] whether the application uses MongoDB (wires up mongoid config)
    field :has_mongodb, type: Mongoid::Boolean, default: false

    # @!attribute [rw] has_redis
    #   @return [Boolean] whether the application uses Redis
    field :has_redis, type: Mongoid::Boolean, default: false

    # @!attribute [rw] master_key
    #   @return [String, nil] Rails `RAILS_MASTER_KEY` value (32 hex chars); encrypted credentials support
    field :master_key, type: String, default: nil

    # @!attribute [rw] additional_components
    #   @return [Array<Symbol>] extra component symbols required beyond the guest's defaults
    field :additional_components, type: Array, default: []

    enum_field :build_state, {
      0x00 => :pending,
      0x01 => :running,
      0x02 => :checking_out,
      0x03 => :bundling,
      0x04 => :building_assets,
      0x05 => :packaging,
      0x06 => :storing,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    field :build_last_issue, type: String

    enum_field :redeploy_state, {
      0x00 => :pending,
      0x01 => :running,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started

    field :redeploy_last_issue, type: String

    # @!attribute [rw] file
    #   @return [Mongoid::GridFS::Fs::File, nil] the packaged tarball stored in GridFS
    belongs_to :file, class_name: "Mongoid::GridFS::Fs::File", optional: true

    validates :name, presence: true, uniqueness: true
    validates :git_server, presence: true
    validates :git_repo, presence: true
    validates :git_branch, presence: true
    validates :master_key, length: {is: 32}, allow_blank: true

    used_in_guests_as 'services.deploy_web_image_id'

    def services
      services = []
      used_in_guests.each do |guest|
        guest.services.where('deploy_web_image_id': id).each do |service|
          services << service
        end
      end
      services
    end

    # @return [Integer, nil] size of the stored GridFS file in bytes
    def file_size
      file.try :length
    end

    def build_path
      Pathname.new(CloudModel.config.data_directory).join('build', 'web_images', id).to_s
    end

    def build_gem_home
      "#{build_path}/shared/bundle/#{Bundler.ruby_scope}"
    end

    def build_gemfile
      "#{build_path}/current/Gemfile"
    end

    def worker
      CloudModel::Workers::WebImageWorker.new self
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
        CloudModel::WebImageJobs::BuildJob.perform_later id.to_s
      rescue Exception => e
        update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    def build!(options = {})
      unless buildable? or options[:force]
        return false
      end

      self.build_state = :pending

      worker.build options
    end

    def self.redeployable_redeploy_states
      [:finished, :failed, :not_started]
    end

    def redeployable?
      self.class.redeployable_redeploy_states.include? redeploy_state
    end

    def redeploy(options = {})
      unless redeployable? or options[:force]
        return false
      end

      update_attribute :redeploy_state, :pending

      services.each do |service|
        if service.redeployable? or options[:force]
          service.update_attribute :redeploy_web_image_state, :pending
        end
      end

      begin
        CloudModel::WebImageJobs::RedeployJob.perform_later id.to_s
      rescue Exception => e
        update_attributes redeploy_state: :failed, redeploy_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
        return false
      end
    end

    def redeploy!(options = {})
      unless redeployable? or options[:force]
        return false
      end

      self.redeploy_state = :pending

      services.each do |service|
        if service.redeployable? or options[:force]
          service.redeploy_web_image_state = :pending
        end
      end

      worker.redeploy options
    end
  end
end
