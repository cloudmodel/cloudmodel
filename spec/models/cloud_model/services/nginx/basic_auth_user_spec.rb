require 'spec_helper'

describe CloudModel::Services::Nginx::BasicAuthUser do
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:password_hash).of_type String }
  it { expect(subject).to be_embedded_in(:service).of_type CloudModel::Services::Nginx }

  it 'stores only an nginx {SSHA} hash of the password' do
    subject.password = 'opensesame'

    expect(subject.password_hash).to start_with '{SSHA}'
    expect(subject.password_hash).not_to include 'opensesame'
    expect(subject.attributes.keys).not_to include 'password'
  end

  it 'hashes as nginx checks it: base64(SHA-1(password + salt) + salt)' do
    hash = described_class.hash_password 'opensesame', 'saltsalt'

    expect(hash).to eq "{SSHA}#{Base64.strict_encode64(Digest::SHA1.digest('opensesamesaltsalt') + 'saltsalt')}"
  end

  it 'salts every hash' do
    expect(described_class.hash_password('opensesame')).not_to eq described_class.hash_password('opensesame')
  end

  it 'verifies the password against the hash' do
    subject.password = 'opensesame'

    expect(subject.password_matches?('opensesame')).to eq true
    expect(subject.password_matches?('demo')).to eq false
  end

  it 'keeps the stored hash when a blank password is assigned' do
    subject.password = 'opensesame'
    hash = subject.password_hash
    subject.password = ''

    expect(subject.password_hash).to eq hash
  end

  it 'needs a password for a new login' do
    subject.name = 'demo'

    expect(subject).not_to be_valid
    expect(subject.errors[:password]).to be_present
  end

  it 'rejects names the htpasswd format cannot hold' do
    subject.password = 'opensesame'
    ['de:mo', 'de mo', ''].each do |name|
      subject.name = name
      expect(subject).not_to be_valid
      expect(subject.errors[:name]).to be_present
    end
  end

  it 'renders its htpasswd line' do
    subject.name = 'demo'
    subject.password_hash = '{SSHA}abc'

    expect(subject.htpasswd_line).to eq 'demo:{SSHA}abc'
  end
end
