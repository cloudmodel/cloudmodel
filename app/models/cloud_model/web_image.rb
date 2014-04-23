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
    
    before_save :build
    
    field :name, type: String
    field :git_server, type: String
    field :git_repo, type: String
    field :git_branch, type: String, default: 'master'
    field :git_commit, type: String
    field :has_assets, type: Mongoid::Boolean, default: false
    field :has_mongodb, type: Mongoid::Boolean, default: false    
    field :has_redis, type: Mongoid::Boolean, default: false    

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
      @build_path ||= if Rails.env.development? or Rails.env.test?
        "/tmp/build/#{id}"
      else
        Rails.root.join('..', '..', 'shared', 'build', id).to_s
      end
    end
    
    def build_gem_home
      "#{build_path}/shared/bundle/#{Bundler.ruby_scope}"
    end
    
    def build_gemfile
      "#{build_path}/current/Gemfile"
    end
  end
end
  