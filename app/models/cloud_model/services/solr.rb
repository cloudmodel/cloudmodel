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
            
      def livestatus
        if guest.livestatus
          guest.livestatus.services.find{|s| s.description == 'SOLR'}
        end
      end
      
      def heap_size
        "#{guest.memory_size / 1024 / 1024 - 128}m"
      end
    end
  end
end