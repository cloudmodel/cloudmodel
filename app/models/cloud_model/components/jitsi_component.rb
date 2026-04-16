module CloudModel
  module Components
    # Component that installs the Jitsi stack (Meet, Videobridge, Jicofo) into a guest template.
    #
    # Requires nginx and Java 11.
    class JitsiComponent < BaseComponent
      # @return [Symbol] always `:jitsi`
      def name
        :jitsi
      end

      # @return [Array<Symbol>] `[:nginx, :"java@11"]`
      def requirements
        [:'nginx', :'java@11']
      end
    end
  end
end