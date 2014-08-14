require 'spec_helper'

describe CloudModel::HostWorker do
  it 'should assign host parameter' do
    host = Factory :host
    worker = CloudModel::HostWorker.new host
    expect(worker.instance_variable_get '@host').to eq host
  end
  
  let(:host) { Factory :host }
  subject { CloudModel::HostWorker.new host }
  
  context 'create_image' do
    pending
  end

  context 'copy_config' do
    pending
  end
  
  context 'config_firewall' do
    pending
  end
  
  context 'config_fstab' do
    pending
  end
  
  context 'config_libvirt_guests' do
    pending
  end
  
  context 'boot_deploy_root' do
    pending
  end
  
  context 'update_tinc_host_files' do
    pending
  end
  
  context 'make_deploy_root' do
    pending
  end
  
  context 'make_keys' do
    pending
  end
  
  context 'copy_keys' do
    pending
  end
  
  context 'deploy' do
    pending
  end
  
  context 'redeploy' do
    pending
  end
end