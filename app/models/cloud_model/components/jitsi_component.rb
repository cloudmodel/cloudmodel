module CloudModel
  module Components
    class JitsiComponent < BaseComponent
      def name
        :jitsi
      end

      def requirements
        [:'nginx', :'java@11']
      end
    end
  end
end