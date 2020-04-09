require 'spec_helper'

describe CloudModel::ExecutionException do
  subject { CloudModel::ExecutionException.new 'command', 'error', 'output' }
  it { expect(subject).to be_a Exception }
  
  describe 'initialize' do
    it 'should store command, error and output' do
      exception = CloudModel::ExecutionException.new '/sbin/command --failed', 'Command failed to execute', 'Error 42: It failed' 
      expect(exception.command).to eq '/sbin/command --failed'
      expect(exception.error).to eq 'Command failed to execute'
      expect(exception.output).to eq 'Error 42: It failed' 
    end
  end
end