require 'spec_helper'

describe CloudModel::Workers::Services::NginxWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:model) {CloudModel::Services::Nginx.new}
  subject {CloudModel::Workers::Services::NginxWorker.new guest, model}

  describe '.unroll_web_image' do
    pending
  end

  describe '.make_deploy_web_image_id' do
    pending
  end

  describe '.deploy_web_image' do
    pending
  end

  describe '.redeploy_web_image' do
    pending
  end

  describe '.deploy_web_locations' do
    pending
  end

  describe '.write_config' do
    pending
  end

  describe '.service_name' do
    it 'should return nginx' do
      expect(subject.service_name).to eq 'nginx'
    end
  end

  describe '.auto_restart' do
    it 'should return true' do
      expect(subject.auto_restart).to eq true
    end
  end

  describe '.auto_start' do
    pending
  end
end