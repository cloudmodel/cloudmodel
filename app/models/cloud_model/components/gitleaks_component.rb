module CloudModel
  module Components
    # Component that installs gitleaks (secret scanner) into a guest template,
    # versioned as `gitleaks@<release>`. Used by the Forgejo service's
    # pre-receive secret scanning and available to CI guests.
    class GitleaksComponent < BaseComponent
    end
  end
end
