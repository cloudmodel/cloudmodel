module CloudModel
  module Workers
    module Components
      class BaseComponentWorker < CloudModel::Workers::BaseWorker
        def initialize template, host, options={}
          #super host, options
          @template = template
          @host = host
          @options = options
        end
      end
    end
  end
end