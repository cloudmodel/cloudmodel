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

    it 'should record a monitoring sample after storing' do
      check_subject = Factory :certificate
      subject.instance_variable_set :@subject, check_subject
      allow(subject).to receive(:data).and_return 'data' => 'some data'

      expect(subject).to receive(:record_sample)
      subject.store_data
    end

    it 'should raise and print errors when update_attributes fails' do
      allow(subject).to receive(:data).and_return 'data' => 'some data'
      errors = double 'errors', as_json: {'name' => ['is invalid']}
      allow(check_subject).to receive(:update_attributes).and_return false
      allow(check_subject).to receive(:errors).and_return errors

      expect do
        expect { subject.store_data }.to raise_error('Failed to store monitoring data')
      end.to output(/is invalid/).to_stdout
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

    it 'should print FAILED if store_data returns false' do
      expect(subject).to receive(:acquire_data).and_return 'data' => 'some data'
      expect(subject).to receive(:store_data).and_return false

      expect do
        expect(subject.data).to eq 'data' => 'some data'
      end.to output("  * Acqire data ...\n    -> \e[32mOK\e[39m\n  * Store data ...\n    -> \e[33mFAILED\e[39m\n").to_stdout
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

  describe 'sample_metrics' do
    it 'should be empty by default' do
      expect(subject.sample_metrics).to eq({})
    end
  end

  describe 'flatten_numeric' do
    it 'should flatten nested numeric values into dotted keys' do
      data = {a: 1, b: {c: 2.5, d: {e: 3}}}
      expect(subject.flatten_numeric(data)).to eq 'a' => 1.0, 'b.c' => 2.5, 'b.d.e' => 3.0
    end

    it 'should map booleans to 1.0 / 0.0' do
      expect(subject.flatten_numeric({up: true, down: false})).to eq 'up' => 1.0, 'down' => 0.0
    end

    it 'should skip strings and arrays' do
      expect(subject.flatten_numeric({a: 'text', b: [1, 2], c: 4})).to eq 'c' => 4.0
    end

    it 'should return an empty hash for non-hash input' do
      expect(subject.flatten_numeric(nil)).to eq({})
      expect(subject.flatten_numeric(false)).to eq({})
    end
  end

  describe 'record_sample' do
    it 'should record the sample metrics for the subject' do
      allow(subject).to receive(:sample_metrics).and_return 'cpu.load_1' => 1.5
      allow(check_subject).to receive(:monitoring_last_check_at).and_return Time.now

      expect(CloudModel::MonitoringSample).to receive(:record!).with(check_subject, {'cpu.load_1' => 1.5}, at: check_subject.monitoring_last_check_at)
      subject.record_sample
    end

    it 'should do nothing when there are no metrics' do
      allow(subject).to receive(:sample_metrics).and_return({})
      expect(CloudModel::MonitoringSample).not_to receive(:record!)
      subject.record_sample
    end

    it 'should swallow errors so sampling never breaks monitoring' do
      allow(subject).to receive(:sample_metrics).and_return 'cpu.load_1' => 1.5
      allow(check_subject).to receive(:monitoring_last_check_at).and_return Time.now
      allow(CloudModel::MonitoringSample).to receive(:record!).and_raise 'boom'

      expect { expect { subject.record_sample }.not_to raise_error }.to output(/Failed to record monitoring sample/).to_stdout
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

  describe 'do_check_above_value' do
    before do
      allow(subject).to receive(:do_check)
    end

    it 'should set check to true when value is below threshold' do
      expect(subject).to receive(:do_check).with(:disk_free, 'Disk free', {critical: true}, anything)
      subject.do_check_above_value :disk_free, 5, {critical: 10}
    end

    it 'should set check to false when value is at or above threshold' do
      expect(subject).to receive(:do_check).with(:disk_free, 'Disk free', {critical: false}, anything)
      subject.do_check_above_value :disk_free, 20, {critical: 10}
    end

    it 'should format float values with 2 decimal places' do
      expect(subject).to receive(:do_check).with(:disk_free, anything, anything, hash_including(value: '5.30%'))
      subject.do_check_above_value :disk_free, 5.3, {}, unit: '%'
    end

    it 'should build default message from name and value' do
      expect(subject).to receive(:do_check).with(:disk_free, 'Disk free', anything, hash_including(message: 'Disk free is 5%'))
      subject.do_check_above_value :disk_free, 5, {}, unit: '%'
    end

    it 'should use custom name when provided' do
      expect(subject).to receive(:do_check).with(:disk_free, 'Free space', anything, anything)
      subject.do_check_above_value :disk_free, 5, {}, name: 'Free space'
    end
  end

  describe 'self.handle_cloudmodel_monitoring_exception' do
    let(:issue) { double 'ItemIssue', persisted?: false }

    before do
      allow(CloudModel::ItemIssue).to receive(:find_or_initialize_by).and_return issue
    end

    it 'should resolve the issue and return true when the block succeeds' do
      allow(issue).to receive(:resolved_at=)

      result = CloudModel::Monitoring::BaseChecks.handle_cloudmodel_monitoring_exception 'a subject', nil, 0 do
        :ok
      end

      expect(result).to eq true
    end

    it 'should save a persisted issue when resolving' do
      persisted_issue = double 'ItemIssue', persisted?: true
      allow(CloudModel::ItemIssue).to receive(:find_or_initialize_by).and_return persisted_issue
      allow(persisted_issue).to receive(:resolved_at=)
      expect(persisted_issue).to receive(:save)

      CloudModel::Monitoring::BaseChecks.handle_cloudmodel_monitoring_exception 'a subject', nil, 0 do
        :ok
      end
    end

    it 'should record the exception and return false when the block raises' do
      expect(issue).to receive(:severity=).with(:warning)
      expect(issue).to receive(:message=)
      expect(issue).to receive(:value=).with('boom')
      expect(issue).to receive(:save)

      result = nil
      expect do
        result = CloudModel::Monitoring::BaseChecks.handle_cloudmodel_monitoring_exception 'a subject', nil, 2 do
          raise 'boom'
        end
      end.to output(/crashed/).to_stdout

      expect(result).to eq false
    end

    it 'should derive a per-symbol key and null out the subject when subject is a symbol' do
      allow(issue).to receive(:resolved_at=)
      expect(CloudModel::ItemIssue).to receive(:find_or_initialize_by).with(
        key: :check_crashed_my_service, resolved_at: nil, subject: nil
      ).and_return issue

      CloudModel::Monitoring::BaseChecks.handle_cloudmodel_monitoring_exception :my_service, nil, 0 do
        :ok
      end
    end

    it 'should prefix output with a string host name on crash' do
      allow(issue).to receive(:severity=)
      allow(issue).to receive(:message=)
      allow(issue).to receive(:value=)
      allow(issue).to receive(:save)

      expect do
        CloudModel::Monitoring::BaseChecks.handle_cloudmodel_monitoring_exception 'subj', 'myhost', 0 do
          raise 'boom'
        end
      end.to output(/\[myhost\] /).to_stdout
    end

    it 'should prefix output with the host object name on crash' do
      allow(issue).to receive(:severity=)
      allow(issue).to receive(:message=)
      allow(issue).to receive(:value=)
      allow(issue).to receive(:save)
      host = double 'Host', name: 'objhost'

      expect do
        CloudModel::Monitoring::BaseChecks.handle_cloudmodel_monitoring_exception 'subj', host, 0 do
          raise 'boom'
        end
      end.to output(/\[objhost\] /).to_stdout
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