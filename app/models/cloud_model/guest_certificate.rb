module CloudModel
  # Join record that attaches a {Certificate} to a {Guest} at specific file paths.
  #
  # Unlike service-level `ssl_cert_id` references, a GuestCertificate places
  # the certificate and key at explicit paths inside the container's filesystem,
  # making them available to any process running in the guest.
  class GuestCertificate
    include Mongoid::Document
    include Mongoid::Timestamps
    prepend CloudModel::Mixins::SmartToString

    # @!attribute [rw] guest
    #   @return [CloudModel::Guest] the guest that receives this certificate
    belongs_to :guest, class_name: "CloudModel::Guest"

    # @!attribute [rw] certificate
    #   @return [CloudModel::Certificate] the certificate to deploy
    belongs_to :certificate, class_name: "CloudModel::Certificate"

    # @!attribute [rw] path_to_crt
    #   @return [String] absolute path inside the container where the .crt file is written
    field :path_to_crt, type: String

    # @!attribute [rw] path_to_key
    #   @return [String] absolute path inside the container where the .key file is written
    field :path_to_key, type: String

    # Returns a combined name from guest and certificate names.
    # @return [String] e.g. `"app-01 wildcard.example.com"`
    def name
      "#{guest.name} #{certificate.name}"
    end
  end
end