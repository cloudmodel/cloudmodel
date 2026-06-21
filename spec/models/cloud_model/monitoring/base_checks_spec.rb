# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::BaseChecks do
  let(:check_subject) { double to_s: 'Check Object' }
  subject { CloudModel::Monitoring::BaseChecks.new check_subject, skip_header: true }

  describe 'initialize' do
    it 'should output a header for the subject' do
      expect do
        checks = CloudModel::Monitoring::BaseChecks.new check_subject
      end.to output("[Check Object]\n").to_stdout
    end

    it 'should not output a header for the subject if :skip_header is set' do
      expect do
        checks = CloudModel::Monitoring::BaseChecks.new check_subject, skip_header: true
      end.to output("").to_stdout
    end

    it 'should set instance variable for subject' do
      checks = CloudModel::Monitoring::BaseChecks.new check_subject, skip_header: true

      expect(checks.instance_variable_get :@subject).to eq check_subject
    end

    it 'should set instance variable for options' do
      options = {cached: true, skip_header: true}
      checks = CloudModel::Monitoring::BaseChecks.new check_subject, options
      expect(checks.instance_variable_get :@subject).to eq check_subject
      expect(checks.instance_variable_get :@options).to eq options
    end
  end

  describe 'indent_size' do
    it 'should be 0' do
      expect(subject.indent_size).to eq 0
    end
  end

  describe 'acquire_data' do
    it 'should be nil' do
      expect(subject.acquire_data).to eq nil
    end
  end

  describe 'store_data' do
    it 'should store data on subject' do
      check_subject = Factory :certificate
      subject.instance_variable_set :@subject, check_subject

      expect(subject).to receive(:data).and_return 'data' => 'some data'
      expect(subject.store_data).to eq true

      expect(check_subject.monitoring_last_check_result).to eq 'data' => 'some data'
      check_subject.reload
      expect(check_subject.monitoring_last_check_result).to eq 'data' => 'some data'
    end
  end

  describe 'data' do
    it 'should acquire data and store it on first run' do
      expect(subject).to receive(:acquire_data).and_return 'data' => 'some data'
      expect(subject).to receive(:store_data).and_return true

      expect do
        expect(subject.data).to eq 'data' => 'some data'
      end.to output("  * Acqire data ...\n    -> \e[32mOK\e[39m\n  * Store data ...\n    -> \e[32mOK\e[39m\n").to_stdout
    end

    it 'should acquire data as false and not store that on first run if acquire_data is nil' do
      expect(subject).to receive(:acquire_data).and_return nil
      expect(subject).not_to receive(:store_data)

      expect do
        expect(subject.data).to eq false
      end.to output("  * Acqire data ...\n    -> \e[32mOK\e[39m\n").to_stdout
    end


    it 'should pulls monitoring_last_check_result from check subject if option :cached is set' do
      subject.instance_variable_set :@options, cached: true
      expect(check_subject).to receive(:monitoring_last_check_result).and_return 'data' => 'some data'

      expect do
        expect(subject.data).to eq 'data' => 'some data'
      end.to output('').to_stdout
    end


    it 'should pulls monitoring_last_check_result from check subject if option :cached is set, and return false if monitoring_last_check_result was nil' do
      subject.instance_variable_set :@options, cached: true
      expect(check_subject).to receive(:monitoring_last_check_result).and_return nil

      expect do
        expect(subject.data).to eq false
      end.to output('').to_stdout
    end

    it 'should not pull/acquire data once it was loaded' do
      subject.instance_variable_set :@data, 'data' => 'some data'

      expect do
        expect(subject.data).to eq 'data' => 'some data'
      end.to output('').to_stdout
    end
  end

  describe 'line_prefix' do
    it 'should be the indention' do
      allow(subject).to receive(:indent_size).and_return 2
      expect(subject.line_prefix).to eq '  '
      allow(subject).to receive(:indent_size).and_return 6
      expect(subject.line_prefix).to eq '      '
    end
  end

  describe 'do_check' do
    let(:issue) { double 'ItemIssue', persisted?: false }
    let(:issues) { double 'item_issues' }

    before do
      allow(check_subject).to receive(:item_issues).and_return issues
      allow(issues).to receive(:find_or_initialize_by).and_return issue
    end

    it 'should return true and resolve issue when no checks are truthy' do
      allow(issue).to receive(:resolved_at=)

      expect do
        expect(subject.do_check(:test_key, 'Test Check', {})).to eq true
      end.to output(/OK/).to_stdout
    end

    it 'should save persisted issue when resolving' do
      persisted_issue = double 'ItemIssue', persisted?: true
      allow(issues).to receive(:find_or_initialize_by).and_return persisted_issue
      allow(persisted_issue).to receive(:resolved_at=)
      expect(persisted_issue).to receive(:save)

      expect { subject.do_check :test_key, 'Test Check', {} }.to output(/OK/).to_stdout
    end

    it 'should not save non-persisted issue when resolving' do
      allow(issue).to receive(:resolved_at=)
      expect(issue).not_to receive(:save)

      expect { subject.do_check :test_key, 'Test Check', {} }.to output(/OK/).to_stdout
    end

    it 'should return false and set severity when a check is truthy' do
      allow(issue).to receive(:severity=)
      allow(issue).to receive(:message=)
      allow(issue).to receive(:value=)
      allow(issue).to receive(:save)

      expect do
        expect(subject.do_check(:test_key, 'Test Check', {warning: true})).to eq false
      end.to output(/WARNING/).to_stdout
    end

    it 'should set message and value from options' do
      expect(issue).to receive(:severity=).with(:critical)
      expect(issue).to receive(:message=).with('Something broke')
      expect(issue).to receive(:value=).with('42')
      expect(issue).to receive(:save)

      expect do
        subject.do_check :test_key, 'Test Check', {critical: true}, message: 'Something broke', value: '42'
      end.to output(/CRITICAL/).to_stdout
    end

    it 'should use the first truthy severity' do
      expect(issue).to receive(:severity=).with(:warning)
      allow(issue).to receive(:message=)
      allow(issue).to receive(:value=)
      allow(issue).to receive(:save)

      expect do
        subject.do_check :test_key, 'Test Check', {warning: true, critical: false}
      end.to output(/WARNING/).to_stdout
    end
  end

  describe 'do_check_value' do
    before do
      allow(subject).to receive(:do_check)
    end

    it 'should set check to true when value exceeds threshold' do
      expect(subject).to receive(:do_check).with(:mem, 'Mem', {warning: true}, anything)
      subject.do_check_value :mem, 90, {warning: 80}
    end

    it 'should set check to false when value is below threshold' do
      expect(subject).to receive(:do_check).with(:mem, 'Mem', {warning: false}, anything)
      subject.do_check_value :mem, 50, {warning: 80}
    end

    it 'should format float values with 2 decimal places' do
      expect(subject).to receive(:do_check).with(:mem, anything, anything, hash_including(value: '75.30%'))
      subject.do_check_value :mem, 75.3, {}, unit: '%'
    end

    it 'should build default message from name and value' do
      expect(subject).to receive(:do_check).with(:mem, 'Mem', anything, hash_including(message: 'Mem is 75%'))
      subject.do_check_value :mem, 75, {}, unit: '%'
    end

    it 'should use custom name when provided' do
      expect(subject).to receive(:do_check).with(:mem, 'Memory', anything, anything)
      subject.do_check_value :mem, 75, {}, name: 'Memory'
    end
  end

  describe 'do_check_for_errors_on' do
    before do
      allow(subject).to receive(:do_check)
    end

    it 'should call do_check with severity when result key matches an error case' do
      result = {key: :service_down, severity: :critical, error: 'Service crashed'}
      expect(subject).to receive(:do_check).with(:service_down, 'Service status', {critical: true}, message: 'Service crashed')
      subject.do_check_for_errors_on result, {service_down: 'Service status'}
    end

    it 'should default severity to warning when not specified' do
      result = {key: :service_down, error: 'Down'}
      expect(subject).to receive(:do_check).with(:service_down, 'Service status', {warning: true}, message: 'Down')
      subject.do_check_for_errors_on result, {service_down: 'Service status'}
    end

    it 'should call do_check with empty checks for non-matching error cases' do
      result = {key: :service_down, error: 'Down'}
      expect(subject).to receive(:do_check).with(:service_down, 'Service status', {warning: true}, message: 'Down')
      expect(subject).to receive(:do_check).with(:config_error, 'Config', {})
      subject.do_check_for_errors_on result, {service_down: 'Service status', config_error: 'Config'}
    end

    it 'should mark all as OK when result key matches none' do
      result = {key: :other}
      expect(subject).to receive(:do_check).with(:svc, 'Service', {})
      subject.do_check_for_errors_on result, {svc: 'Service'}
    end
  end
end