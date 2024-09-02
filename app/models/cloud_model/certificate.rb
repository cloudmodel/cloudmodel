module CloudModel
  # Handle certificates
  class Certificate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString
    # Add guests connected via GuestCertificates
    module CertificateUsedInGuest
      # Get Guests using this certificate
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

    # @return [String] Define the name of the certificate
    field :name, type: String
    # @return [String] Define the CA of the certificate
    field :ca, type: String
    # @return [String] Define the CA of the certificate
    field :key, type: String
    # @return [String] Define the CA of the certificate
    field :crt, type: String
    # @return [Time] Define the CA of the certificate
    field :valid_from, type: Time
    # @return [Time] Define the CA of the certificate
    field :valid_thru, type: Time

    used_in_guests_as 'services.ssl_cert_id'

    # @!attribute [rw] guest_certificates
    #   @return [CloudModel::GuestCertificate] Define the CA of the certificate
    has_many :guest_certificates, class_name: "CloudModel::GuestCertificate"

    before_save :set_valid_dates

    # Filter for valid certificates
    def self.valid
      scoped.select{|c| c.valid_now?}
    end

    # Get certificate as X509 certificate
    def x509
      begin
        OpenSSL::X509::Certificate.new crt
      rescue
        OpenSSL::X509::Certificate.new
      end
    end

    # Get private key of certificate as PKey
    def pkey
      OpenSSL::PKey.read key
    end

    # Set models valid_from and valid_thru from certificate
    def set_valid_dates
      self.valid_from = x509.not_before
      self.valid_thru = x509.not_after
    end

    # Check if certificate is valid right now
    def valid_now?
      (valid_from.blank? or valid_from < Time.now) and (valid_thru.blank? or Time.now < valid_thru)
    end

    # Get the common name of the certificate
    def common_name
      unless x509.subject.to_a.blank?
        x509.subject.to_a.find{|x| x[0] == "CN"}[1]
      end
    end

    # Get the issuer name of the certificate
    def issuer
      unless x509.issuer.to_a.blank?
        x509.issuer.to_a.find{|x| x[0] == "CN"}[1]
      end
    end

    # Check if private key matches certificate
    def check_key
      x509.check_private_key pkey
    end
  end
end