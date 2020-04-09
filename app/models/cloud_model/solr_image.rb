# SolrImage model
#
# Gets a solr config from a git repository. This repository has to have 2 contents:
#   SOLR_VERSION - a text file containing the required version of solr
#   solr - folder containing the solr config
# every other contents are ignored

module CloudModel
  class SolrImage
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::ENumFields
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString
        
    field :name, type: String
    field :git_server, type: String
    field :git_repo, type: String
    field :git_branch, type: String, default: 'master'
    field :git_commit, type: String
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
    
    def file_size
      file.try :length
    end
    
    def solr_mirror
      CloudModel::SolrMirror.find_by(version: solr_version)
    end
    
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
        CloudModel::call_rake 'cloudmodel:solr_image:build', solr_image_id: id
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
  