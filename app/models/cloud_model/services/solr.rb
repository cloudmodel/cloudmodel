module CloudModel
  module Services
    class Solr < Base
      field :port, type: Integer, default: 8080
      belongs_to :deploy_solr_image, class_name: 'CloudModel::SolrImage', inverse_of: :services
      
      
      def kind
        :http
      end
      
      def components_needed
        [:java, :solr]
      end
      
      def shinken_services_append
        ', solr'
      end
      
      def livestatus
        if guest.livestatus
          guest.livestatus.services.find{|s| s.description == 'SOLR'}
        end
      end
    end
  end
end