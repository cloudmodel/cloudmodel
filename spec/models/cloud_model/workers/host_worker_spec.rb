require 'spec_helper'

describe CloudModel::Workers::HostWorker do
  it 'should assign host parameter' do
    host = Factory :host
    worker = CloudModel::Workers::HostWorker.new host
    expect(worker.instance_variable_get '@host').to eq host
  end

  let(:host) { Factory :host }
  subject { CloudModel::Workers::HostWorker.new host }

  describe 'create_image' do
    pending
  end

  describe 'copy_config' do
    pending
  end

  describe 'config_firewall' do
    pending
  end

  describe 'config_fstab' do
    pending
  end

  describe 'config_libvirt_guests' do
    pending
  end

  describe 'boot_deploy_root' do
    pending
  end

  describe 'update_tinc_host_files' do
    pending
  end

  describe 'make_deploy_root' do
    pending
  end

  describe 'update_tinc' do
    pending
  end

  describe 'make_keys' do
    pending
  end

  describe 'copy_keys' do
    pending
  end

  describe 'deploy' do
    pending
  end

  describe 'redeploy' do
    pending
  end
end