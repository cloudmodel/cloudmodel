module CloudModel
  module Monitoring
    # Expiry of certificates placed into guests as files ({GuestCertificate}),
    # e.g. SAML or OAuth signing certificates. Certificates an nginx service
    # serves are checked live from the TLS handshake by NginxChecks; these
    # files are never served, so nothing else would notice them expire.
    # Same thresholds as the nginx check: warning a month ahead, critical a
    # week ahead, fatal once expired.
    class CertificateChecks < CloudModel::Monitoring::BaseChecks
      def self.check options = {}
        certificates_in_guests.each do |certificate|
          handle_cloudmodel_monitoring_exception certificate, '_Certificate_', 2 do
            CloudModel::Monitoring::CertificateChecks.new(certificate).check
          end
        end
      end

      # Certificates attached to at least one existing guest as a file.
      # @return [Array<CloudModel::Certificate>]
      def self.certificates_in_guests
        guest_ids = CloudModel::Guest.pluck(:id)
        certificate_ids = CloudModel::GuestCertificate.where(:guest_id.in => guest_ids).distinct(:certificate_id)
        CloudModel::Certificate.where(:id.in => certificate_ids).to_a
      end

      def line_prefix
        "[_Certificate_] #{super}"
      end

      def acquire_data
        guest_ids = CloudModel::GuestCertificate.where(certificate_id: @subject.id).distinct(:guest_id)
        {
          valid_thru: @subject.valid_thru,
          guests: CloudModel::Guest.where(:id.in => guest_ids).pluck(:name).compact.sort
        }
      end

      def check
        return if data[:valid_thru].blank? # no certificate data (key-only entry)

        do_check_above_value :cert_valid_after, data[:valid_thru], {
          fatal: Time.now,
          critical: Time.now + 1.week,
          warning: Time.now + 1.month
        }, name: 'Certificate valid until',
          message: "#{@subject.name} valid until #{data[:valid_thru].to_date}, placed in #{data[:guests] * ', '}"
      end
    end
  end
end
