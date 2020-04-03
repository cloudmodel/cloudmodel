# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::BaseChecks do
  let(:check_subject) { double to_s: 'Check Object' }
  subject { CloudModel::Monitoring::BaseChecks.new check_subject, skip_header: true }
  
  context 'initialize' do
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
  
  context 'indent_size' do
    it 'should be 0' do
      expect(subject.indent_size).to eq 0
    end
  end
  
  context 'aquire_data' do
    it 'should be nil' do
      expect(subject.aquire_data).to eq nil
    end
  end
  
  context 'store_data' do
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

  context 'data' do
    it 'should aquire data and store it on first run' do
      expect(subject).to receive(:aquire_data).and_return 'data' => 'some data'
      expect(subject).to receive(:store_data)
    
      expect do
        expect(subject.data).to eq 'data' => 'some data'
      end.to output("  * Acqire data ...[\e[32mOK\e[39m]\n").to_stdout
    end
    
    it 'should aquire data as false and not store that on first run if aquire_data is nil' do
      expect(subject).to receive(:aquire_data).and_return nil
      expect(subject).not_to receive(:store_data)
    
      expect do
        expect(subject.data).to eq false
      end.to output("  * Acqire data ...[\e[32mOK\e[39m]\n").to_stdout
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
    
    it 'should not pull/aquire data once it was loaded' do
      subject.instance_variable_set :@data, 'data' => 'some data'
      
      expect do
        expect(subject.data).to eq 'data' => 'some data'
      end.to output('').to_stdout
    end
  end
  
  context 'do_check' do
  end
  
  context 'do_check_value' do
  end
  
  context 'do_check_errors_on' do
  end
end