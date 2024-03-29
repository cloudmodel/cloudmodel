require 'spec_helper'

describe CloudModel::Workers::Services::PhpfpmWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {double CloudModel::Services::Phpfpm}
  subject {CloudModel::Workers::Services::PhpfpmWorker.new lxc, model}

  describe 'patch_php_ini' do
    pending
  end

  describe 'write_config' do
    pending
  end

  describe 'service_name' do
    it 'should return php-fpm' do
      expect(subject.service_name).to eq 'php-fpm'
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