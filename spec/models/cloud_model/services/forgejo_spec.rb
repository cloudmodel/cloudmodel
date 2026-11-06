# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Forgejo do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:port).of_type(Integer).with_default_value_of 3000 }
  it { expect(subject).to have_field(:default_theme).of_type(String).with_default_value_of "forgejo-auto" }
  it { expect(subject).to have_field(:logo_svg).of_type(String) }
  it { expect(subject).to have_field(:secret_key).of_type(String) }
  it { expect(subject).to have_field(:internal_token).of_type(String) }
  it { expect(subject).to have_field(:lfs_jwt_secret).of_type(String) }
  it { expect(subject).to have_field(:oauth_jwt_secret).of_type(String) }

  describe 'kind' do
    it 'should return :forgejo' do
      expect(subject.kind).to eq :forgejo
    end
  end

  describe 'allow_public_service?' do
    it 'should allow public exposure' do
      expect(subject.allow_public_service?).to eq true
    end
  end

  it { expect(subject).to have_field(:forgejo_version).of_type(String) }
  it { expect(subject).to have_field(:external_login_only).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:oidc_scopes).of_type(String).with_default_value_of 'openid profile email groups' }
  it { expect(subject).to have_field(:oidc_group_claim).of_type(String).with_default_value_of 'groups' }
  it { expect(subject).to have_field(:oidc_admin_group).of_type(String) }
  it { expect(subject).to have_field(:oidc_restricted_group).of_type(String) }
  it { expect(subject).to have_field(:oidc_group_team_map).of_type(String) }
  it { expect(subject).to have_field(:oidc_group_team_map_removal).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:oidc_skip_local_2fa).of_type(Mongoid::Boolean).with_default_value_of false }
  it { expect(subject).to have_field(:oidc_auto_registration).of_type(Mongoid::Boolean).with_default_value_of true }
  it { expect(subject).to have_field(:oidc_account_linking).of_type(String).with_default_value_of 'login' }
  it { expect(subject).to have_field(:mailer_enabled).of_type(Mongoid::Boolean).with_default_value_of true }
  it { expect(subject).to have_field(:packages_enabled).of_type(Mongoid::Boolean).with_default_value_of true }
  it { expect(subject).to have_field(:actions_enabled).of_type(Mongoid::Boolean).with_default_value_of true }
  it { expect(subject).to have_field(:actions_default_url).of_type(String).with_default_value_of 'https://data.forgejo.org' }

  it { expect(subject).to validate_inclusion_of(:oidc_account_linking).to_allow('disabled', 'login', 'auto') }

  describe 'components_needed' do
    it 'should require the forgejo component of the default (LTS) release' do
      expect(subject.components_needed).to eq [:"forgejo@15.0.11"]
    end

    it 'should pin the release set on the service' do
      subject.forgejo_version = '15.0.12'
      expect(subject.components_needed).to eq [:"forgejo@15.0.12"]
    end
  end

  describe 'oidc?' do
    it 'should need name, discovery url and client id' do
      expect(subject.oidc?).to eq false
      subject.oidc_name = 'sso'
      subject.oidc_auto_discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
      subject.oidc_client_id = 'client'
      expect(subject.oidc?).to eq true
    end
  end

  describe 'external_login_only?' do
    it 'should only take effect with a configured OIDC source' do
      subject.external_login_only = true
      expect(subject.external_login_only?).to eq false
      subject.oidc_name = 'sso'
      subject.oidc_auto_discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
      subject.oidc_client_id = 'client'
      expect(subject.external_login_only?).to eq true
    end
  end

  describe 'oidc_scope_list' do
    it 'should split the scopes on blanks and commas' do
      subject.oidc_scopes = 'openid, profile email  groups'
      expect(subject.oidc_scope_list).to eq %w[openid profile email groups]
    end
  end

  describe 'oidc_group_team_map validation' do
    it 'should accept a JSON object' do
      subject.oidc_group_team_map = '{"developers": {"org": ["developers"]}}'
      subject.valid?
      expect(subject.errors[:oidc_group_team_map]).to be_empty
    end

    it 'should reject anything that is not a JSON object' do
      subject.oidc_group_team_map = '[1,2]'
      subject.valid?
      expect(subject.errors[:oidc_group_team_map]).not_to be_empty

      subject.oidc_group_team_map = 'not json'
      subject.valid?
      expect(subject.errors[:oidc_group_team_map]).not_to be_empty
    end
  end

  describe 'backups' do
    it { expect(subject.backupable?).to eq true }
    it { expect(subject.backup_data_mount_point).to eq 'var/lib/forgejo' }
  end

  describe 'runner_registration_command' do
    let(:runner) { CloudModel::Services::ForgejoRunner.new runner_name: 'ci', registration_secret: 'a' * 40, labels: ['ubuntu-latest:host', 'self-hosted:host'] }

    it 'should register the runner as the forgejo user with its secret and label names, without an inner shell' do
      expect(subject.runner_registration_command(runner)).to eq "runuser -u forgejo -- env GITEA_WORK_DIR\\=/var/lib/forgejo GITEA_CUSTOM\\=/etc/forgejo/custom forgejo --config /etc/forgejo/app.ini forgejo-cli actions register --name ci --labels ubuntu-latest,self-hosted --secret #{'a' * 40}"
    end

    it 'should scope the runner when a scope is set' do
      runner.scope = 'myorg'
      expect(subject.runner_registration_command(runner)).to end_with ' --scope myorg'
    end
  end

  describe 'oidc_login_source_flags' do
    before do
      subject.oidc_name = 'sso'
      subject.oidc_auto_discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
      subject.oidc_client_id = 'client'
      subject.oidc_client_secret = 'se cret'
      subject.oidc_admin_group = 'admins'
      subject.oidc_group_team_map = '{"staff": {"org": ["staff"]}}'
      subject.oidc_skip_local_2fa = true
    end

    it 'should carry every mapping flag (empty when unset) and one --scopes per scope' do
      flags = subject.oidc_login_source_flags
      expect(flags).to include('--provider', 'openidConnect', '--key', 'client', '--secret', 'se cret', '--skip-local-2fa=true', '--group-claim-name', 'groups', '--admin-group', 'admins', '--restricted-group', '', '--group-team-map', '{"staff": {"org": ["staff"]}}', '--group-team-map-removal=false')
      expect(flags.each_cons(2).count { |k, v| k == '--scopes' }).to eq 4
      expect(Shellwords.join(flags)).to include("--secret se\\ cret")
    end
  end

  describe 'used_ports' do
    it 'should return the configured tcp port' do
      subject.port = 3000
      expect(subject.used_ports).to eq [[3000, :tcp]]
    end
  end

  describe 'service_status' do
    let(:guest) { double CloudModel::Guest, private_address: '10.42.0.1' }
    before { allow(subject).to receive(:guest).and_return(guest) }

    it 'should return error hash when HTTP fails' do
      allow(Net::HTTP).to receive(:start).and_raise(Errno::ECONNREFUSED)

      result = subject.service_status
      expect(result[:key]).to eq :not_reachable
      expect(result[:severity]).to eq :critical
    end

    it 'should return warning on 404' do
      response = double 'response', code: '404', body: ''
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })

      result = subject.service_status
      expect(result[:key]).to eq :not_found
      expect(result[:severity]).to eq :warning
    end

    it 'should parse prometheus metrics into a hash' do
      body = "# HELP some help\nforgejo_users 5\nforgejo_repos 12\n"
      response = double 'response', code: '200', body: body
      allow(Net::HTTP).to receive(:start).and_yield(double('http').tap { |h| allow(h).to receive(:request).and_return(response) })

      result = subject.service_status
      expect(result['forgejo_users']).to eq '5'
      expect(result['forgejo_repos']).to eq '12'
    end
  end
end
