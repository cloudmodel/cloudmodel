module CloudModel
  class GuestTemplateType
    include Mongoid::Document
    include Mongoid::Timestamps

    has_many :templates, class_name: 'CloudModel::GuestTemplate'
    
    field :name
    field :components, type: Array
    
    def build(options = {})
      return false
      
      # unless deployable? or options[:force]
      #   return false
      # end
      #
      # update_attribute :deploy_state, :pending
      #
      # begin
      #   CloudModel::call_rake 'cloudmodel:guest:redeploy', host_id: host_id, guest_id: id
      # rescue Exception => e
      #   update_attributes deploy_state: :failed, deploy_last_issue: 'Unable to enqueue job! Try again later.'
      #   CloudModel.log_exception e
      # end
    end
  
    def build!(host, options={})
      guest_worker = CloudModel::GuestTemplateWorker.new host
      guest_worker.build_new_template self, options
    end
    
    def last_useable(host, options={})
      template = templates.where(arch: host.arch, build_state_id: 0xf0).last
      unless template
        guest_worker = CloudModel::GuestTemplateWorker.new host
        template = guest_worker.build_new_template self, options
      end
      template
    end

  end
end