# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::NginxChecks do
  let(:host) { double CloudModel::Host, name: 'testhost' }
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Nginx, guest: guest }
  subject { CloudModel::Monitoring::Services::NginxChecks.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::Services::BaseChecks }

  describe 'check' do
    it 'should check for nginx specific errors' do
      test_data = {key: :ok}
      allow(subject).to receive(:data).and_return test_data
      allow(subject).to receive(:do_check_for_errors_on)

      subject.check

      expect(subject).to have_received(:do_check_for_errors_on).with(test_data, {
        not_reachable: 'service reachable',
        no_nginx_status: 'status available',
        ngnix_status_forbidden: 'status forbidden',
        parse_result: 'parse status'
      })
    end

    it 'should not check ssl cert when no ssl_cert data' do
      test_data = {key: :ok}
      allow(subject).to receive(:data).and_return test_data
      allow(subject).to receive(:do_check_for_errors_on)

      expect(subject).not_to receive(:do_check_value)
      expect(subject).not_to receive(:do_check_above_value)

      subject.check
    end

    it 'should check ssl cert validity when ssl_cert data present' do
      not_after = Time.now + 1.year
      not_before = Time.now - 1.year
      not_after_obj = double(to_time: not_after)
      not_before_obj = double(to_time: not_before)

      test_data = {key: :ok, 'ssl_cert' => {'not_after' => not_after_obj, 'not_before' => not_before_obj}}
      allow(subject).to receive(:data).and_return test_data
      allow(subject).to receive(:do_check_for_errors_on)
      allow(subject).to receive(:do_check_value)
      allow(subject).to receive(:do_check_above_value)

      subject.check

      expect(subject).to have_received(:do_check_value).with(:cert_valid_before, not_before, hash_including(:fatal))
      expect(subject).to have_received(:do_check_above_value).with(:cert_valid_after, not_after, hash_including(:fatal, :critical, :warning))
    end
  end
end