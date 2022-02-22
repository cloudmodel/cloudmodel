module CloudModel
  class SshPubKey
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    field :key, type: String
    validates :key, presence: true, uniqueness: true

    has_and_belongs_to_many :groups, class_name: CloudModel::SshGroup, inverse_of: :pub_keys

    def self.from_file(filename)
      File.readlines(filename).each do |line|
        CloudModel::SshPubKey.create! key: line.strip
      end
    end

    def name
      key.split(' ').last
    end
  end
end