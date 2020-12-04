require 'spec_helper'

describe CloudModel::ConfigModules::Api do
  it 'should have api version 1.0' do
    expect(subject.api_version).to eq '1.0'
  end
end