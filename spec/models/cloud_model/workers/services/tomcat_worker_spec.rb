require 'spec_helper'

describe CloudModel::Workers::Services::TomcatWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:model) {CloudModel::Services::Tomcat.new}
  subject {CloudModel::Workers::Services::TomcatWorker.new guest, model}

  describe 'write_config' do
    pending
  end

  describe 'service_name' do
    it 'should return tomcat8' do
      expect(subject.service_name).to eq 'tomcat8'
    end
  end

  describe 'interpolate_value' do
    pending
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