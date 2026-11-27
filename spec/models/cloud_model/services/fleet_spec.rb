# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Fleet do
  let(:guest) { CloudModel::Guest.new name: 'fleet06' }
  subject { CloudModel::Services::Fleet.new admin_email: 'admin@example.com' }

  before do
    allow(guest).to receive(:external_hostname).and_return 'fleet.example.com'
    allow(subject).to receive(:guest).and_return guest
  end

  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 8080 }
  it { expect(subject).to have_field(:fleet_version).of_type(String) }
  it { expect(subject).to have_field(:telemetry).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:sso_jit_provisioning).of_type(Mongoid::Boolean).with_default_value_of true }

  it { expect(subject.kind).to eq :fleet }

  it { expect(subject).to have_field(:cisa_known_exploits_url).of_type(String).with_default_value_of(nil) }

  it 'should accept a blank or an http(s) URL for the CISA known exploits catalog only' do
    subject.cisa_known_exploits_url = 'ftp://example.com/kev.json'
    subject.valid?
    expect(subject.errors[:cisa_known_exploits_url]).not_to be_empty
    subject.cisa_known_exploits_url = 'https://example.com/kev.json'
    subject.valid?
    expect(subject.errors[:cisa_known_exploits_url]).to be_empty
  end

  it 'should never be public itself (nginx in front is)' do
    expect(subject.allow_public_service?).to eq false
  end

  describe 'components_needed' do
    it 'should require the fleet component only (the database is a service of its own)' do
      expect(subject.components_needed).to eq [:"fleet@4.96.0"]
    end

    it 'should pin the release set on the service' do
      subject.fleet_version = '4.97.0'
      expect(subject.components_needed).to eq [:"fleet@4.97.0"]
    end
  end

  describe 'validation' do
    it 'should need an administrator email' do
      subject.admin_email = nil
      guest.services << CloudModel::Services::Redis.new
      guest.services << CloudModel::Services::Mysql.new
      expect(subject).not_to be_valid
      expect(subject.errors[:admin_email]).not_to be_empty
    end

    it 'should need a Redis and a Percona Server service in the guest' do
      expect(subject).not_to be_valid
      expect(subject.errors[:base]).to include 'needs a Redis service in the same guest'
      expect(subject.errors[:base]).to include 'needs a MySQL service in the same guest (Fleet does not run on MariaDB)'
    end

    it 'should be valid with Redis and Percona Server in the guest and use the server´s port' do
      guest.services << CloudModel::Services::Redis.new
      guest.services << CloudModel::Services::Mysql.new(port: 3307)
      expect(subject).to be_valid
      expect(subject.database_port).to eq 3307
    end

    it 'should need a guest with an external hostname (the server URL)' do
      guest.services << CloudModel::Services::Mysql.new
      guest.services << CloudModel::Services::Redis.new
      allow(guest).to receive(:external_hostname).and_return ''

      expect(subject).not_to be_valid
      expect(subject.errors[:base]).to include 'needs a guest with an external address (its hostname is Fleet\'s server URL)'
    end

    it 'should use the port of the guest´s Redis' do
      expect(subject.redis_port).to eq 6379
      guest.services << CloudModel::Services::Redis.new(port: 6380)
      expect(subject.redis_port).to eq 6380
    end

    it 'should refuse a host without a Fleet server build' do
      guest.services << CloudModel::Services::Redis.new
      guest.services << CloudModel::Services::Mysql.new
      allow(guest).to receive(:host).and_return CloudModel::Host.new(arch: 'arm64')
      expect(subject).not_to be_valid
      expect(subject.errors[:base]).to include 'Fleet publishes its server for amd64 only, this host is arm64'
    end

    it 'should not be backed up itself (the database server is)' do
      expect(subject.backupable?).to eq false
    end
  end

  describe 'urls and names' do
    it { expect(subject.root_url).to eq 'https://fleet.example.com' }
    it { expect(subject.api_email).to eq 'cloudmodel-api@fleet.example.com' }
    it { expect(subject.effective_org_name).to eq 'fleet06' }
    it { expect(subject.effective_sso_entity_id).to eq 'fleet.example.com' }
    it { expect(subject.used_ports).to eq [[8080, :tcp]] }
  end

  describe 'generate_secrets' do
    it 'should generate all missing secrets once' do
      expect(subject.generate_secrets).to eq true
      expect(subject.database_password.size).to eq 32
      expect(Base64.strict_decode64(subject.server_private_key).bytesize).to eq 32
      expect(subject.enroll_secret.size).to eq 32
      expect(subject.admin_password).to match(/[a-z]/).and match(/[A-Z]/).and match(/[0-9]/).and match(/[^A-Za-z0-9]/)

      secrets = subject.attributes.slice('database_password', 'server_private_key', 'enroll_secret', 'admin_password')
      expect(subject.generate_secrets).to eq false
      expect(subject.attributes.slice(*secrets.keys)).to eq secrets
    end
  end

  describe 'provision_specs' do
    before { subject.enroll_secret = 'enroll-me' }

    it 'should converge enroll secret, organisation, server url and switch analytics off' do
      expect(subject.provision_specs).to eq [
        { 'apiVersion' => 'v1', 'kind' => 'enroll_secret', 'spec' => { 'secrets' => [{ 'secret' => 'enroll-me' }] } },
        { 'apiVersion' => 'v1', 'kind' => 'config', 'spec' => {
          'org_info' => { 'org_name' => 'fleet06' },
          'server_settings' => { 'server_url' => 'https://fleet.example.com', 'enable_analytics' => false },
          'sso_settings' => { 'enable_sso' => false }
        } }
      ]
    end

    it 'should switch analytics on with telemetry' do
      subject.telemetry = true
      expect(subject.provision_specs.last['spec']['server_settings']['enable_analytics']).to eq true
    end

    it 'should configure SAML single sign-on when identity provider and metadata are set' do
      subject.sso_idp_name = 'Company SSO'
      subject.sso_metadata_url = 'https://idp.example.com/saml/metadata'
      expect(subject.provision_specs.last['spec']['sso_settings']).to eq(
        'enable_sso' => true,
        'idp_name' => 'Company SSO',
        'entity_id' => 'fleet.example.com',
        'metadata_url' => 'https://idp.example.com/saml/metadata',
        'enable_jit_provisioning' => true
      )
    end
  end

  describe 'service_status' do
    before { allow(guest).to receive(:private_address).and_return '10.42.0.1' }

    it 'should report healthy on 200' do
      expect(subject).to receive(:monitoring_http_get).with('http://10.42.0.1:8080/healthz').and_return double(code: '200')
      expect(subject.service_status).to eq(healthy: true)
    end

    it 'should report an unhealthy backend' do
      allow(subject).to receive(:monitoring_http_get).and_return double(code: '500', body: 'mysql down')
      expect(subject.service_status).to include(key: :not_healthy, severity: :critical)
    end

    it 'should report an unreachable service' do
      allow(subject).to receive(:monitoring_http_get).and_raise Errno::ECONNREFUSED
      expect(subject.service_status).to include(key: :not_reachable, severity: :critical)
    end
  end
end
