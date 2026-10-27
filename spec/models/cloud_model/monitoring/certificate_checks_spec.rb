# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::CertificateChecks do
  let(:certificate) { double CloudModel::Certificate, id: BSON::ObjectId.new, name: 'SAML signing 2023' }
  subject { CloudModel::Monitoring::CertificateChecks.new certificate, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe 'check' do
    def with_validity valid_thru
      allow(subject).to receive(:data).and_return valid_thru: valid_thru, guests: ['auth04', 'auth05']
    end

    it 'is fatal for an expired certificate and names the guests' do
      with_validity Time.now - 1.day
      expect(subject).to receive(:do_check).with(:cert_valid_after, 'Certificate valid until', hash_including(fatal: true), hash_including(message: /SAML signing 2023 valid until .* placed in auth04, auth05/))
      subject.check
    end

    it 'is critical within a week of expiry' do
      with_validity Time.now + 3.days
      expect(subject).to receive(:do_check).with(:cert_valid_after, anything, {fatal: false, critical: true, warning: true}, anything)
      subject.check
    end

    it 'warns within a month of expiry' do
      with_validity Time.now + 20.days
      expect(subject).to receive(:do_check).with(:cert_valid_after, anything, {fatal: false, critical: false, warning: true}, anything)
      subject.check
    end

    it 'passes a certificate valid for longer' do
      with_validity Time.now + 90.days
      expect(subject).to receive(:do_check).with(:cert_valid_after, anything, {fatal: false, critical: false, warning: false}, anything)
      subject.check
    end

    it 'skips entries without certificate data' do
      with_validity nil
      expect(subject).not_to receive(:do_check)
      subject.check
    end
  end

  describe '.certificates_in_guests' do
    it 'returns certificates placed into existing guests only' do
      used = Factory :certificate
      orphaned = Factory :certificate
      Factory :certificate # not placed anywhere
      guest = Factory :guest
      CloudModel::GuestCertificate.create! guest: guest, certificate: used, path_to_crt: '/etc/ssl/a.crt', path_to_key: '/etc/ssl/a.key'
      CloudModel::GuestCertificate.new(guest_id: BSON::ObjectId.new, certificate: orphaned, path_to_crt: '/etc/ssl/b.crt', path_to_key: '/etc/ssl/b.key').save(validate: false)

      expect(described_class.certificates_in_guests).to eq [used]
    end
  end

  describe '.check' do
    it 'checks every certificate placed into a guest' do
      real = Factory :certificate
      allow(described_class).to receive(:certificates_in_guests).and_return [real]
      checks = double check: true
      expect(described_class).to receive(:new).with(real).and_return checks
      expect(checks).to receive(:check)
      described_class.check
    end
  end
end
