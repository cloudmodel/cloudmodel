module CloudModel
  module Monitoring
    class CertificateChecks < CloudModel::Monitoring::BaseChecks
      def initialize certificate, options = {}
        puts "[Certificate #{certificate.name}]"
        @indent = 0
        @subject = certificate
      end
    
      def check
        
      end
    end
  end
end