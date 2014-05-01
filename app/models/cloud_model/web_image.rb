module CloudModel
  class ExecutionException < Exception
    attr_accessor :command, :error, :output
    def initialize(command, error, output)
      @command = command
      @error = error
      @output = output
    end
  end
  
  class WebImage
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::UsedInGuestsAs
    include CloudModel::ENumFields
        
    field :name, type: String
    field :git_server, type: String
    field :git_repo, type: String
    field :git_branch, type: String, default: 'master'
    field :git_commit, type: String
    field :has_assets, type: Mongoid::Boolean, default: false
    field :has_mongodb, type: Mongoid::Boolean, default: false    
    field :has_redis, type: Mongoid::Boolean, default: false    
    
    enum_field :build_state, values: {
      0x00 => :pending,
      0x01 => :running,
      0xf0 => :finished,
      0xf1 => :failed,
      0xff => :not_started
    }, default: :not_started
    
    field :build_last_issue, type: String

    belongs_to :file, class_name: "Mongoid::GridFS::Fs::File"
    
    validates :name, presence: true, uniqueness: true
    validates :git_server, presence: true
    validates :git_repo, presence: true
    validates :git_branch, presence: true
    
    used_in_guests_as 'services.deploy_web_image_id'
    
    def file_size
      file.try :length
    end
    
    def build_path 
      Rails.root.join('data', 'build', 'web_images', id).to_s
    end
    
    def build_gem_home
      "#{build_path}/shared/bundle/#{Bundler.ruby_scope}"
    end
    
    def build_gemfile
      "#{build_path}/current/Gemfile"
    end
    
    
    def build
      begin
        CloudModel::call_rake 'cloudmodel:web_image:build', web_image_id: id
      rescue Exception => e
        update_attributes build_state: :failed, build_last_issue: 'Unable to enqueue job! Try again later.'
        CloudModel.log_exception e
      end
    end
    
  end
end
  