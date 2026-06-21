require 'spec_helper'

describe CloudModel do
  describe '#config' do
    it 'should return a CloudModel::Config instance' do
      expect(CloudModel.config).to be_a CloudModel::Config
    end

    it 'should memoize the config instance' do
      expect(CloudModel.config).to be CloudModel.config
    end
  end

  describe '#configure' do
    it 'should yield config to the block' do
      CloudModel.configure do |config|
        expect(config).to be_a CloudModel::Config
      end
    end

    it 'should allow setting config values' do
      CloudModel.configure do |config|
        config.admin_email = 'test@example.com'
      end
      expect(CloudModel.config.admin_email).to eq 'test@example.com'
    end
  end
  
  describe '#log_exception' do
  end
end 

