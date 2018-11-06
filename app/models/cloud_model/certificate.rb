module CloudModel
  class Certificate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::UsedInGuestsAs
    # Add guests connected via GuestCertificates
    module CertificateUsedInGuest
      def used_in_guests
        guest_ids = guest_certificates.pluck(:guest_id)
        if guest_ids.blank?
          super
        else
          CloudModel::Guest.or(super, :id.in => guest_ids)
        end
      end
    end
    include CertificateUsedInGuest
    
    field :name, type: String
    field :ca, type: String
    field :key, type: String
    field :crt, type: String
    field :valid_thru, type: Date
    
    used_in_guests_as 'services.ssl_cert_id'
    
    has_many :guest_certificates, class_name: "CloudModel::GuestCertificate"
    
    #scope :valid, -> { where(:valid_thru.gt => Time.now) }
    
    def self.valid
      all.select{|c| c.valid_now?}
    end
    
    def to_s
      name
    end
    
    def x509
      begin
        OpenSSL::X509::Certificate.new crt
      rescue
        OpenSSL::X509::Certificate.new
      end
    end
    
    def pkey
      OpenSSL::PKey.read key
    end
    
    def valid_from
      x509.not_before
    end
    
    def valid_thru
      x509.not_after
    end
    
    def valid_now?
      valid_from < Time.now and Time.now < valid_thru
    end
    
    def common_name
      unless x509.subject.to_a.blank?
        x509.subject.to_a.find{|x| x[0] == "CN"}[1]
      end
    end
    
    def issuer
      unless x509.issuer.to_a.blank?
        x509.issuer.to_a.find{|x| x[0] == "CN"}[1]
      end
    end
    
    def check_key
      x509.check_private_key pkey
    end
  end
end