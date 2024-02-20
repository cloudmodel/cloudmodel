# encoding: UTF-8

require 'spec_helper'
require 'net/ftp'

describe CloudModel::Workers::Components::FusekiComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::FusekiComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    let(:ftp) { double login:true, chdir:true, list: ['fuseki.tar.gz'], pwd: '/Mirrors/ftp.apache.org/dist/jena/binaries', close: true }
    before do
      allow(subject).to receive :chroot!
      allow(Net::FTP).to receive(:new).and_return ftp
    end

    it 'should get latest fuseki' do
      expect(Net::FTP).to receive(:new).with('ftp-stud.hs-esslingen.de').and_return ftp
      expect(ftp).to receive(:login)
      expect(ftp).to receive(:chdir).with 'Mirrors/ftp.apache.org/dist/jena/binaries/'
      expect(ftp).to receive(:list).with('apache-jena-fuseki-*.tar.gz').and_return [
        '-rw-r--r--    1 1003     1003     54674820 Jul 09 19:06 apache-jena-fuseki-3.16.0.tar.gz',
        '-rw-r--r--    1 1003     1003     54674820 Jul 09 19:06 apache-jena-fuseki-42.23.0.tar.gz'
      ]
      expect(ftp).to receive(:close)

      expect(subject).to receive(:chroot!).with(
        '/tmp/build',
        'cd /opt && ' +
        'wget -q ftp://ftp-stud.hs-esslingen.de/Mirrors/ftp.apache.org/dist/jena/binaries/apache-jena-fuseki-42.23.0.tar.gz && '+
        'tar xzf apache-jena-fuseki-42.23.0.tar.gz && '+
        'mv apache-jena-fuseki-42.23.0 fuseki && '+
        'rm apache-jena-fuseki-42.23.0.tar.gz',
        'Failed to download fuseki')

      subject.build '/tmp/build'
    end

    it 'should add user fuseki' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "useradd fuseki -d /var/lib/fuseki -m -r -k /dev/null -c 'Fuseki User'", 'Failed to add user fuseki')

      subject.build '/tmp/build'
    end
  end
end