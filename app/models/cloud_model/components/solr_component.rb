module CloudModel
  module Components
    class SolrComponent < BaseComponent
      def name
        :solr
      end

      def requirements
        if @version and @version > '8.'
          [:'java@11']
        else
          [:'java@8']
        end
      end
    end
  end
end