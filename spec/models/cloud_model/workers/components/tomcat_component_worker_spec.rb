# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::TomcatComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::TomcatComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :render_to_remote
      allow(subject).to receive :chroot!
    end

    it 'should apt-get tomcat' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install tomcat8 tomcat8-admin -y', 'Failed to install tomcat')

      subject.build '/tmp/build'
    end

    it 'should config CA' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "/var/lib/dpkg/info/ca-certificates-java.postinst configure", 'Failed to config CA certs for tomcat')

      subject.build '/tmp/build'
    end

    it 'should setup systemd service' do
      expect(subject).to receive(:render_to_remote).with("/cloud_model/guest/bin/tomcat8", "/tmp/build/usr/sbin/tomcat8", 0755)
      expect(subject).to receive(:render_to_remote).with("/cloud_model/guest/etc/systemd/system/tomcat8.service", "/tmp/build/etc/systemd/system/tomcat8.service")

      subject.build '/tmp/build'
    end
  end
end