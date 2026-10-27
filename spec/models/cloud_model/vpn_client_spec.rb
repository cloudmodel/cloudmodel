# encoding: UTF-8

require 'spec_helper'

describe CloudModel::VpnClient do
  it { expect(subject).to have_timestamps }
  it { expect(subject).to have_field(:name).of_type String }
  it { expect(subject).to have_field(:tinc_public_key).of_type String }
  it { expect(subject).to have_field(:address).of_type String }
  it { expect(subject).to have_field(:os).of_type String }

  it { expect(subject).to validate_presence_of(:name) }
  it { expect(subject).to validate_uniqueness_of(:name) }
  it { expect(subject).to validate_format_of(:name).to_allow("host-name-01") }
  it { expect(subject).to validate_format_of(:name).not_to_allow("Test Host") }
  it { expect(subject).to validate_presence_of(:tinc_public_key) }
  it { expect(subject).to validate_presence_of(:address) }
  it { expect(subject).to validate_format_of(:address).to_allow("127.0.0.1") }
  it { expect(subject).to validate_format_of(:address).not_to_allow("256.2.1.2") }

  describe 'tinc host file sync' do
    let(:client) { CloudModel::VpnClient.new name: "dev-#{SecureRandom.hex(3)}", tinc_public_key: 'KEY', address: '10.42.253.4' }

    it 'enqueues the host file update when a client is created' do
      expect(CloudModel::HostJobs::UpdateTincHostFilesJob).to receive(:perform_later)
      client.save!
    end

    it 'enqueues the host file update when the key changes' do
      allow(CloudModel::HostJobs::UpdateTincHostFilesJob).to receive(:perform_later)
      client.save!
      expect(CloudModel::HostJobs::UpdateTincHostFilesJob).to receive(:perform_later)
      client.update! tinc_public_key: 'NEW KEY'
    end

    it 'does not enqueue for changes the hosts do not see' do
      allow(CloudModel::HostJobs::UpdateTincHostFilesJob).to receive(:perform_later)
      client.save!
      expect(CloudModel::HostJobs::UpdateTincHostFilesJob).not_to receive(:perform_later)
      client.update! os: 'macOS'
    end

    it 'enqueues the host file update when a client is deleted' do
      allow(CloudModel::HostJobs::UpdateTincHostFilesJob).to receive(:perform_later)
      client.save!
      expect(CloudModel::HostJobs::UpdateTincHostFilesJob).to receive(:perform_later)
      client.destroy
    end

    it 'does not fail the save when the job cannot be enqueued' do
      allow(CloudModel::HostJobs::UpdateTincHostFilesJob).to receive(:perform_later).and_raise 'queue down'
      allow(CloudModel).to receive(:log_exception)
      expect(client.save).to eq true
    end
  end

  describe 'config_tarball' do
    it 'should return a StringIO tar archive' do
      subject.name = 'test-client'
      controller = double 'controller'
      allow(ActionController::Base).to receive(:new).and_return(controller)
      allow(controller).to receive(:render_to_string).and_return('rendered content')
      allow(CloudModel::Host).to receive(:each).and_yield(double(name: 'host1', tinc_public_key: 'key'))

      result = subject.config_tarball
      expect(result).to be_a StringIO
    end

    it 'should ship the OpenSSL legacy config for tinc on OpenSSL 3' do
      subject.name = 'test-client'
      allow(CloudModel::Host).to receive(:each)
      names = []
      Gem::Package::TarReader.new(StringIO.new(subject.config_tarball.string)) { |tar| tar.each { |e| names << e.full_name } }
      expect(names).to include 'openssl-legacy.cnf'
    end
  end
end