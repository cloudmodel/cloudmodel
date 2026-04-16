module CloudModel
  module Components
    # Component that installs Microsoft Core Fonts into a guest template.
    #
    # **IMPORTANT:** Using this component means accepting the Microsoft EULA for
    # the Core Fonts package. By instantiating this component you confirm that
    # you have read and agreed to the End-User License Agreement for Microsoft
    # Software accompanying the fonts (Arial, Courier New, Times New Roman, etc.).
    class MsCoreFontsComponent < BaseComponent

      def requirements
        []
      end
    end
  end
end