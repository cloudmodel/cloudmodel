module CloudModel
  class BaseWorker
    include AbstractController::Rendering
    
    def render template, locals={}
      av = ActionView::Base.new
      av.view_paths = ActionController::Base.view_paths
      av.render(template: template, locals: locals)
    end
  end
end