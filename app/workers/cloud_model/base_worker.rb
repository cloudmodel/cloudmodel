module CloudModel
  class BaseWorker
    include AbstractController::Rendering
    
    def render template, locals={}
      av = ActionView::Base.new
      av.view_paths = ActionController::Base.view_paths
      av.render(template: template, locals: locals)
    end
    
    def mkdir_p path
      @host.exec! "mkdir -p #{path.shellescape}", "Failed to make directory #{path}"
    end
  
    def build_tar src, dst, options = {}
      def parse_param param, value
        params = ''

        if value == true
          params << "-#{param.size>1 ? '-' : ''}#{param} "
        elsif value.class == Array
          value.each do |i|
            params << parse_param(param, i)
          end
        else
          params << "-#{param.size>1 ? '-' : ''}#{param} #{value.shellescape} "
        end

        params
      end

      cmd = "tar cf #{dst.shellescape} "

      options.each do |k,v|
        param = k.to_s.gsub('_', '-').shellescape

        cmd << parse_param(param, v)
      end
      cmd << "#{src.shellescape}"

      @host.exec! cmd, "Failed to build tar #{dst}"
    end
  end
end