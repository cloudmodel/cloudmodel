# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::SolrWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Solr.new}
  subject {CloudModel::Workers::Services::SolrWorker.new lxc, model}

  describe 'write_config' do
    pending
  end

  describe 'service_name' do
    it 'should return solr' do
      expect(subject.service_name).to eq 'solr'
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