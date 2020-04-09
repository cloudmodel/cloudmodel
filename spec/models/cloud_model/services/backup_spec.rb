# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::Backup do
  it { expect(subject).to be_a CloudModel::Services::Base }
    
  describe 'kind' do
    it 'should return :headless' do
      expect(subject.kind).to eq :headless
    end
  end
  
  describe 'components_needed' do
    it 'should require ruby components' do
      expect(subject.components_needed).to eq [:ruby]
    end
  end

  describe 'service_status' do 
    pending
  end
end