module CloudModel
  module Components
    # Component that installs Apache Solr into a guest template.
    #
    # Automatically selects the required Java version based on the Solr version:
    # Solr 9+ requires Java 21, Solr 8.x requires Java 11, older versions use Java 8.
    class SolrComponent < BaseComponent
      # @return [Symbol] always `:solr` (version is encoded in the {SolrImage}, not here)
      def name
        :solr
      end

      # @return [Array<Symbol>] Java component required by this Solr version
      def requirements
        if @version and @version > '9.'
          [:'java@21']
        elsif @version and @version > '8.'
          [:'java@11']
        else
          [:'java@8']
        end
      end
    end
  end
end