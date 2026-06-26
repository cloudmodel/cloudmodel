# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::ServiceChecks do
  let(:host) {double CloudModel::Host, name: 'testhost'}
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Base, guest: guest }

  subject { CloudModel::Monitoring::ServiceChecks.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe 'indent_size' do
    it 'should indent by 2' do
      expect(subject.indent_size).to eq 2
    end
  end

  describe 'line_prefix' do
    it 'should prefix host name before indention' do
      expect(subject.line_prefix).to eq '[testhost]   '
    end
  end

  describe 'data' do
    it 'should return data from service_check' do
      service_check = double 'service_check'
      allow(service_check).to receive(:data).and_return({key: :ok})
      subject.instance_variable_set :@service_check, service_check

      expect(subject.data).to eq({key: :ok})
    end

    it 'should return nil when no service_check' do
      expect(subject.data).to eq nil
    end
  end

  describe 'check' do
    it 'should instantiate the service-specific check class and call check' do
      allow(service).to receive(:class).and_return(CloudModel::Services::Nginx)
      service_check = double 'service_check'
      allow(CloudModel::Monitoring::Services::NginxChecks).to receive(:new).and_return(service_check)
      allow(service_check).to receive(:check).and_return true
      allow(subject).to receive(:do_check)
      allow(subject).to receive(:check_backup_freshness)

      expect(subject.check).to eq true
    end

    it 'should also run the backup freshness check' do
      allow(service).to receive(:class).and_return(CloudModel::Services::Nginx)
      service_check = double 'service_check', check: true
      allow(CloudModel::Monitoring::Services::NginxChecks).to receive(:new).and_return(service_check)
      allow(subject).to receive(:do_check)

      expect(subject).to receive(:check_backup_freshness)
      subject.check
    end

    it 'should report info issue when check class does not exist' do
      fake_class = double 'class', name: 'CloudModel::Services::Nonexistent'
      allow(service).to receive(:class).and_return(fake_class)
      allow(subject).to receive(:do_check)

      expect(subject).to receive(:do_check).with(:no_check, 'CloudModel::Monitoring::Services::NonexistentChecks exists', {info: true}, anything)

      subject.check
    end
  end
end