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
    
    def state
      if monitoring_last_check_result.blank?
        :undefined
      else
        if item_issues.open.count == 0
          :running
        else
          item_issues.open.desc(:severity_id).first.severity
        end
      end
    end
  end
end
