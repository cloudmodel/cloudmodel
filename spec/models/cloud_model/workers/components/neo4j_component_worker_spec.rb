# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Components::Neo4jComponentWorker do
  let(:template) {double}
  let(:host) {double CloudModel::Host}
  subject {CloudModel::Workers::Components::Neo4jComponentWorker.new template, host}

  it { expect(subject).to be_a CloudModel::Workers::Components::BaseComponentWorker }

  describe '_prepare_neo4j_repository' do
    before do
      allow(subject).to receive :chroot!
    end

    it 'should install key management tools' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install dirmngr gnupg -y', 'Failed to install key management')
      subject._prepare_neo4j_repository '/tmp/build'
    end

    it 'should add neo4j repository to sources list' do
      expect(subject).to receive(:chroot!).with('/tmp/build', "echo 'deb https://debian.neo4j.com stable 4.1' | sudo tee /etc/apt/sources.list.d/neo4j.list", 'Failed to add neo4j to list if repos')
      subject._prepare_neo4j_repository '/tmp/build'
    end

    it 'should add neo4j gpg key' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'wget -q -O - https://debian.neo4j.com/neotechnology.gpg.key | sudo apt-key add - ', 'Failed to add neo4j key')
      subject._prepare_neo4j_repository '/tmp/build'
    end
  end

  describe 'build' do
    before do
      allow(subject).to receive :chroot!
      allow(subject).to receive :_prepare_neo4j_repository
    end

    it 'should prepare the neo4j repository' do
      expect(subject).to receive(:_prepare_neo4j_repository).with('/tmp/build')
      subject.build '/tmp/build'
    end

    it 'should update packages' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get update', 'Failed to update packages')
      subject.build '/tmp/build'
    end

    it 'should install neo4j' do
      expect(subject).to receive(:chroot!).with('/tmp/build', 'apt-get install neo4j -y', 'Failed to install neo4j')
      subject.build '/tmp/build'
    end
  end
end
