module CloudModel
  module Components
    # Component that installs the PHP IMAP extension into a guest template.
    #
    # Requires the `:php` component.
    class PhpImapComponent < BaseComponent
      # @return [String] e.g. `"PHP IMAP"`
      def human_name
        "PHP IMAP #{version}".strip
      end

      # @return [Array<Symbol>] `[:php]`
      def requirements
        [:php]
      end
    end
  end
end