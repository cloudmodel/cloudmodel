# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Certificate do
  it { expect(subject).to have_timestamps }  
    
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:ca).of_type String }
  it { expect(subject).to have_field(:key).of_type String }
  it { expect(subject).to have_field(:crt).of_type String }
  it { expect(subject).to have_field(:valid_from).of_type Time }
  it { expect(subject).to have_field(:valid_thru).of_type Time }


#   scope :valid, -> { where(:valid_thru.gt => Time.now) }

  let(:root_key) {OpenSSL::PKey::RSA.new 2048} # the CA's public/private key

  def new_x509 options = {}
    root_ca = OpenSSL::X509::Certificate.new
    root_ca.version = 2 # cf. RFC 5280 - to make it a "v3" certificate
    root_ca.serial = 1
    root_ca.subject = OpenSSL::X509::Name.parse "/DC=org/DC=ruby-lang/CN=Ruby CA"
    root_ca.issuer = root_ca.subject # root CA's are "self-signed"
    root_ca.public_key = root_key.public_key
    root_ca.not_before = options[:not_before] || Time.now
    root_ca.not_after = options[:not_after] || root_ca.not_before + 2 * 365 * 24 * 60 * 60 # 2 years validity
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = root_ca
    ef.issuer_certificate = root_ca
    root_ca.add_extension(ef.create_extension("basicConstraints","CA:TRUE",true))
    root_ca.add_extension(ef.create_extension("keyUsage","keyCertSign, cRLSign", true))
    root_ca.add_extension(ef.create_extension("subjectKeyIdentifier","hash",false))
    root_ca.add_extension(ef.create_extension("authorityKeyIdentifier","keyid:always",false))
    root_ca.sign(root_key, OpenSSL::Digest::SHA256.new)
    root_ca
  end

  context '#valid' do
    it 'should list all valid certificates' do
      valid_certificates = [
        double(CloudModel::Certificate, 'valid_now?': true),
        double(CloudModel::Certificate, 'valid_now?': true)
      ]
      invalid_certificates = [
        double(CloudModel::Certificate, 'valid_now?': false)        
      ]
      
      allow(CloudModel::Certificate).to receive(:scoped).and_return valid_certificates + invalid_certificates
      expect(CloudModel::Certificate.valid).to eq valid_certificates 
    end
  end

  context 'to_s' do
    it 'should return the name of the Certificate' do
      subject.name = 'TestCertificate'
      expect(subject.to_s).to eq "Certificate 'TestCertificate'"
    end
  end
  
  context 'x509' do
    it 'should get certificate as x509 object' do
      x509 = new_x509
      subject.crt = x509.to_pem
      expect(subject.x509).to eq x509
    end
    
    it 'should return empty x509 object as fallback' do
      expect(subject.x509.class).to eq OpenSSL::X509::Certificate
    end
  end

  context 'pkey' do
    it 'should return key as PKey object' do
      subject.key = root_key.to_pem
      expect(subject.pkey.class).to eq OpenSSL::PKey::RSA
      expect(subject.pkey.to_pem).to eq subject.key
    end
  end
  
  context 'set_valid_dates' do
    it 'should set valid_from to the crt´s one' do
      timestamp = (Time.now - 14.days).change(usec: 0)
      subject.crt = new_x509(not_before: timestamp).to_pem
      subject.set_valid_dates
      expect(subject.valid_from).to eq timestamp
    end
    
    it 'should set valid_thru to the crt´s one' do
      timestamp = (Time.now + 14.days).change(usec: 0)
      subject.crt = new_x509(not_after: timestamp).to_pem
      subject.set_valid_dates
      expect(subject.valid_thru).to eq timestamp
    end
    
    it 'should set valid_thru and valid_from to nil if not crt' do
      subject.set_valid_dates
      expect(subject.valid_from).to eq nil
      expect(subject.valid_thru).to eq nil
    end
    
    it "should be called on save" do
      expect(subject).to receive(:set_valid_dates)
      subject.save
    end
  end

  context 'valid_now?' do
    it 'should be valid if now is between valid_from and valid_thru' do
      subject.valid_from = Time.now - 14.days
      subject.valid_thru = Time.now + 14.days
      expect(subject.valid_now?).to eq true
    end
    
    it 'should not be valid if now is before valid_from' do
      subject.valid_from = Time.now + 4.days
      subject.valid_thru = Time.now + 14.days
      expect(subject.valid_now?).to eq false
    end
    
    it 'should not be valid if now is after valid_thru' do
      subject.valid_from = Time.now - 14.days
      subject.valid_thru = Time.now - 4.days
      expect(subject.valid_now?).to eq false
    end
  end
  
  context 'common_name' do
    it 'should get common name from x509' do
      subject.crt = new_x509.to_pem
      expect(subject.common_name).to eq 'Ruby CA'
    end
    
    it 'should be nil if no crt' do
      expect(subject.common_name).to eq nil
    end
  end

  context 'issuer' do
    it 'should get common name from x509' do
      subject.crt = new_x509.to_pem
      expect(subject.issuer).to eq 'Ruby CA'
    end

    it 'should be nil if no crt' do
      expect(subject.issuer).to eq nil
    end
  end
  
  context 'check_key' do
    it 'should be true if crt and key are the same pair' do
      subject.key = root_key
      subject.crt = new_x509
      expect(subject.check_key).to eq true
    end
    
    it 'should be false if crt and key are the same pair' do
      subject.key = OpenSSL::PKey::RSA.new 2048
      subject.crt = new_x509
      expect(subject.check_key).to eq false
    end
  end

  context 'used_in_guests' do
    it 'should get all guests that has Services using this Certificate' do
      expect(CloudModel::Guest).to receive(:where).with('services.ssl_cert_id' => subject.id).and_return 'LIST OF GUESTS'
      expect(subject.used_in_guests).to eq 'LIST OF GUESTS'
    end
    
    it 'should merge guest_certificates and service certificates' do
      super_query = double
      guest_ids = [BSON::ObjectId.new, BSON::ObjectId.new]
      expect(subject.guest_certificates).to receive(:pluck).with(:guest_id).and_return guest_ids
      
      expect(CloudModel::Guest).to receive(:where).with('services.ssl_cert_id' => subject.id).and_return super_query
      expect(CloudModel::Guest).to receive(:or).with(super_query, :id.in => guest_ids).and_return 'LIST OF GUESTS'
      expect(subject.used_in_guests).to eq 'LIST OF GUESTS'
    end
  end

  context 'used_in_guests_by_hosts' do
    it 'should sort the result of used_in_guests by host and return a Hash' do
      guests = [
        double(CloudModel::Guest, host_id: 'host1'),
        double(CloudModel::Guest, host_id: 'host2'),
        double(CloudModel::Guest, host_id: 'host1')        
      ]    
      allow(subject).to receive(:used_in_guests) { guests }
      
      expect(subject.used_in_guests_by_hosts).to eq({
        'host1' => [guests[0], guests[2]],
        'host2' => [guests[1]],
      })
    end
  end
end