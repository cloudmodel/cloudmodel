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

  describe 'components_needed' do
    it 'should require forgejo component' do
      expect(subject.components_needed).to eq [:forgejo]
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
