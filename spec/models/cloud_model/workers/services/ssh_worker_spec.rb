require 'spec_helper'

describe CloudModel::Workers::Services::SshWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Ssh.new}
  subject {CloudModel::Workers::Services::SshWorker.new lxc, model}

  describe 'write_config' do
    pending
  end

  describe 'service_name' do
    it 'should return sshd' do
      expect(subject.service_name).to eq 'sshd'
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