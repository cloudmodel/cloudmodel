module CloudModel
  module Components
    # Component that installs a JDK/JRE into a guest template.
    #
    # The version string (e.g. `"8"`, `"11"`, `"17"`, `"21"`) selects the
    # OpenJDK release to install.
    class JavaComponent < BaseComponent

    end
  end
end