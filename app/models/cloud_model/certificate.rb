module CloudModel
  # Stores a TLS certificate, its private key, and optional CA chain.
  #
  # A Certificate can be attached to an Nginx service (via `ssl_cert_id`) or
  # mounted directly on a guest (via {GuestCertificate}). The {#valid_from} and
  # {#valid_thru} timestamps are extracted automatically from the X.509 data on
  # save.
  class Certificate
    include Mongoid::Document
    include Mongoid::Timestamps
    include CloudModel::Mixins::UsedInGuestsAs
    include CloudModel::Mixins::HasIssues
    prepend CloudModel::Mixins::SmartToString

    # Extends used_in_guests to include guests connected via GuestCertificates.
    module CertificateUsedInGuest
      # Returns all guests that use this certificate, either directly through
      # {GuestCertificate} records or through a service's `ssl_cert_id`.
      # @return [Mongoid::Criteria<CloudModel::Guest>]
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

    # @!attribute [rw] name
    #   @return [String] human-readable label for this certificate
    field :name, type: String

    # @!attribute [rw] ca
    #   @return [String, nil] PEM-encoded CA / intermediate chain
    field :ca, type: String

    # @!attribute [rw] key
    #   @return [String] PEM-encoded private key
    field :key, type: String

    # @!attribute [rw] crt
    #   @return [String] PEM-encoded X.509 certificate
    field :crt, type: String

    # @!attribute [rw] valid_from
    #   @return [Time] certificate validity start — set automatically from the X.509 data
    field :valid_from, type: Time

    # @!attribute [rw] valid_thru
    #   @return [Time] certificate expiry — set automatically from the X.509 data
    field :valid_thru, type: Time

    used_in_guests_as 'services.ssl_cert_id'

    # @!attribute [r] guest_certificates
    #   @return [Array<CloudModel::GuestCertificate>] join records linking this certificate to guests
    has_many :guest_certificates, class_name: "CloudModel::GuestCertificate"

    before_save :set_valid_dates

    # Returns all certificates whose validity window contains the current time.
    # @return [Array<CloudModel::Certificate>]
    def self.valid
      scoped.select{|c| c.valid_now?}
    end

    # Parses the stored PEM string and returns an OpenSSL X.509 certificate.
    # Returns an empty certificate object if parsing fails.
    # @return [OpenSSL::X509::Certificate]
    def x509
      begin
        OpenSSL::X509::Certificate.new crt
      rescue
        OpenSSL::X509::Certificate.new
      end
    end

    # Parses the stored PEM key and returns an OpenSSL PKey object.
    # @return [OpenSSL::PKey::PKey]
    def pkey
      OpenSSL::PKey.read key
    end

    # Callback: reads `not_before` / `not_after` from the X.509 data and
    # stores them in {#valid_from} and {#valid_thru}.
    def set_valid_dates
      self.valid_from = x509.not_before
      self.valid_thru = x509.not_after
    end

    # Returns true when the certificate validity window includes the current time.
    # A blank `valid_from` or `valid_thru` is treated as unbounded.
    # @return [Boolean]
    def valid_now?
      (valid_from.blank? or valid_from < Time.now) and (valid_thru.blank? or Time.now < valid_thru)
    end

    # Returns the Common Name (CN) from the certificate's subject.
    # @return [String, nil]
    def common_name
      unless x509.subject.to_a.blank?
        x509.subject.to_a.find{|x| x[0] == "CN"}[1]
      end
    end

    # Returns the Common Name (CN) of the certificate's issuer.
    # @return [String, nil]
    def issuer
      unless x509.issuer.to_a.blank?
        x509.issuer.to_a.find{|x| x[0] == "CN"}[1]
      end
    end

    # Verifies that the stored private key matches the stored certificate.
    # @return [Boolean]
    def check_key
      x509.check_private_key pkey
    end
  end
end