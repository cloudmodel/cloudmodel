# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::RedisWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Redis.new}
  subject {CloudModel::Workers::Services::RedisWorker.new lxc, model}

  describe 'write_config' do
    pending
  end

  describe 'service_name' do
    it 'should return redis-server' do
      expect(subject.service_name).to eq 'redis-server'
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