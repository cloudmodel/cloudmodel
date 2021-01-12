# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::BackupWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:model) {CloudModel::Services::Backup.new}
  subject {CloudModel::Workers::Services::BackupWorker.new guest, model}

  describe 'write_config' do
    pending
  end

  describe 'service_name' do
    it 'should return backup' do
      expect(subject.service_name).to eq 'backup'
    end
  end

  describe 'auto_restart' do
    it 'should return false' do
      expect(subject.auto_restart).to eq false
    end
  end

  describe 'auto_start' do
    pending
  end
end