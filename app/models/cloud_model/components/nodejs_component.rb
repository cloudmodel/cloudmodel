module CloudModel
  module Components
    # Node.js plus the JS package managers (npm, yarn). Build-only: apps compile
    # and bundle their JS assets against it, but a deployed app serves the
    # precompiled result, so this stays out of the runtime template. Pulled into
    # a web image's build environment via {WebImage#build_env_template}.
    class NodejsComponent < BaseComponent
      def human_name
        "Node.js #{version}".strip
      end
    end
  end
end
