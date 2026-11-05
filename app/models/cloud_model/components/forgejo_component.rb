module CloudModel
  module Components
    # Component that installs Forgejo into a guest template.
    #
    # The component is versioned (`forgejo@<release>`), so each Forgejo release
    # gets its own template; see {CloudModel::Services::Forgejo#components_needed}.
    class ForgejoComponent < BaseComponent
    end
  end
end
