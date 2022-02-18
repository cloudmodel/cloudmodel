module CloudModel
  module Components
    class PhpImapComponent < BaseComponent
      def human_name
        "PHP IMAP #{version}".strip
      end

      def requirements
        [:php]
      end
    end
  end
end