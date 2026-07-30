module CloudModel
  module Components
    # Component that installs the Jitsi stack (Meet, Videobridge, Jicofo) into a guest template.
    #
    # Requires nginx and Java 17.
    class JitsiComponent < BaseComponent
      # @return [Symbol] always `:jitsi`
      def name
        :jitsi
      end

      # @return [Array<Symbol>] `[:nginx, :"java@17"]`
      def requirements
        [:'nginx', :'java@17']
      end
    end
  end
end