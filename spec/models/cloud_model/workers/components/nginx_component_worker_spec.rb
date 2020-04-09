# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::NginxComponentWorker do
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::NginxComponentWorker.new host}
  
  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }
  
  describe '_prepare_passenger_repository' do
    before do
      allow(subject).to receive :render_to_remote
      allow(subject).to receive :chroot!
    end
    
    it 'should include passenger repository for ubuntu' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install dirmngr gnupg -y", "Failed to install key management").ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 561F9B9CAC40B2F7", "Failed to add fusion key").ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install apt-transport-https ca-certificates software-properties-common -y", "Failed to install ca-certificates").ordered       
      expect(subject).to receive(:render_to_remote).with("/cloud_model/guest/etc/apt/sources.list.d/passenger.list", "/tmp/build/etc/apt/sources.list.d/passenger.list", 600).ordered
    
      subject._prepare_passenger_repository '/tmp/build'
    end  
  end
  
  describe '_prepare_certbot_repository' do
    before do
      allow(subject).to receive :chroot!
    end
    
    it 'should include certbot repository for ubuntu' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "add-apt-repository universe -y", "Failed to add universe repository").ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', "add-apt-repository ppa:certbot/certbot -y", "Failed to add certbot repository").ordered
      
      subject._prepare_certbot_repository '/tmp/build'
    end
  end
  
  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(host).to receive :exec!
    end
    
    it 'should apt-get nginx, passenger, certbot' do
      expect(subject).to receive(:_prepare_passenger_repository).with('/tmp/build').ordered
      expect(subject).to receive(:_prepare_certbot_repository).with('/tmp/build').ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get update", "Failed to update packages").ordered
      expect(subject).to receive(:chroot!).with('/tmp/build', "apt-get install nginx-extras libnginx-mod-http-passenger certbot python-certbot-nginx -y", "Failed to install nginx+passenger+certbot").ordered

      subject.build '/tmp/build'
    end
  end
end