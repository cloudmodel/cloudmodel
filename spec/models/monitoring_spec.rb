require 'spec_helper'

describe CloudModel::Monitoring do
  it 'should have registered checks' do
    checks = CloudModel::Monitoring.instance_variable_get(:@checks)
    expect(checks).to be_a Array
  end
end