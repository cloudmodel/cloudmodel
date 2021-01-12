require 'spec_helper'

describe CloudModel::Workers::Services::MongodbWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:model) {CloudModel::Services::Mongodb.new}
  subject {CloudModel::Workers::Services::MongodbWorker.new guest, model}

  describe 'write_config' do
    pending
  end

  describe 'service_name' do
    it 'should return mongodb' do
      expect(subject.service_name).to eq 'mongodb'
    end
  end

  describe 'auto_restart' do
    it 'should return true' do
      expect(subject.auto_restart).to eq true
    end
  end

  describe 'auto_start' do
    pending
  end
end