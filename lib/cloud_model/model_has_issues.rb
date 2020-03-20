module CloudModel
  module ModelHasIssues
    def self.included(base)
      base.has_many :item_issues, as: :subject, class_name: "CloudModel::ItemIssue"
      base.field :monitoring_last_check_at, type: Time
      base.field :monitoring_last_check_result, type: Hash, default: {}
      base.extend ClassMethods
    end
  
    module ClassMethods  
    end
  end
end
