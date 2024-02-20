# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::FusekiWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Fuseki.new}
  subject {CloudModel::Workers::Services::FusekiWorker.new lxc, model}

  describe 'write_config' do
    pending
  end

  describe 'service_name' do
    it 'should return fuseki' do
      expect(subject.service_name).to eq 'fuseki'
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