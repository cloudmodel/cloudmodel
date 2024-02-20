# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::SolrComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::SolrComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should apt-get lsof' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install lsof -y', 'Failed to install lsof')

      subject.build '/tmp/build'
    end

    it 'should add user solr' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "useradd solr -d /var/solr -r -c 'Solr User'", 'Failed to add user solr')

      subject.build '/tmp/build'
    end
  end
end