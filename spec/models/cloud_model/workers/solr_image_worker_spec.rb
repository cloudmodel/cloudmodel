# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::SolrImageWorker do
  let(:solr_image) do
    double 'SolrImage',
      id: 'solr42',
      build_path: '/tmp/solr_build/solr42',
      git_server: 'git@github.com',
      git_repo: 'org/solr-config',
      git_branch: 'main',
      build_state: :pending,
      file_id: nil
  end

  subject { CloudModel::Workers::SolrImageWorker.new solr_image }

  describe '#checkout_git' do
    before do
      allow(File).to receive(:directory?).with(solr_image.build_path).and_return(true)
      allow(subject).to receive(:run_step).and_return('abc123')
      allow(solr_image).to receive(:update_attribute)
      allow(solr_image).to receive(:update_attributes)
    end

    it 'should pull and update submodules when directory exists' do
      expect(subject).to receive(:run_step).with("Pulling", /git checkout.*git pull/)
      subject.checkout_git
    end

    it 'should update git_commit attribute' do
      expect(solr_image).to receive(:update_attribute).with(:git_commit, 'abc123')
      subject.checkout_git
    end

    it 'should return true on success' do
      expect(subject.checkout_git).to eq true
    end
  end

  describe '#get_solr' do
    it 'should read SOLR_VERSION and find or create mirror' do
      allow(File).to receive(:read).with("#{solr_image.build_path}/SOLR_VERSION").and_return("9.4.0\n")
      mirror = double 'SolrMirror'
      expect(CloudModel::SolrMirror).to receive(:find_or_create_by).with(version: '9.4.0').and_return(mirror)
      subject.get_solr
    end
  end

  describe '#package_build' do
    before do
      allow(subject).to receive(:run_step)
      allow(subject).to receive(:system).and_return(true)
    end

    it 'should package solr-config directory when it exists' do
      allow(File).to receive(:exist?).with("#{solr_image.build_path}/solr-config").and_return(true)
      expect(subject).to receive(:run_step).with("Packaging", /solr-config/)
      expect(subject.package_build).to eq true
    end

    it 'should package solr directory when solr-config does not exist' do
      allow(File).to receive(:exist?).with("#{solr_image.build_path}/solr-config").and_return(false)
      expect(subject).to receive(:run_step).with("Packaging", /\/solr /)
      expect(subject.package_build).to eq true
    end
  end

  describe '#build' do
    it 'should return false if not pending and not forced' do
      allow(solr_image).to receive(:build_state).and_return(:running)
      expect(subject.build).to eq false
    end

    it 'should run full build pipeline when pending' do
      allow(solr_image).to receive(:update_attributes)
      allow(subject).to receive(:checkout_git).and_return(true)
      allow(subject).to receive(:get_solr).and_return(true)
      allow(subject).to receive(:package_build).and_return(true)
      file = double 'GridFsFile', id: 'file123'
      allow(Mongoid::GridFs).to receive(:put).and_return(file)
      subject.instance_variable_set :@solr_version, '9.4.0'

      expect(solr_image).to receive(:update_attributes).with(build_state: :running, build_last_issue: nil)
      expect(solr_image).to receive(:update_attributes).with(build_state: :finished)
      expect(subject.build).to eq true
    end
  end

  describe '#run_step' do
    it 'should execute command and return output on success' do
      allow(Rails.logger).to receive(:debug)
      allow(subject).to receive(:`) { `true`; 'test output' }

      expect(subject.run_step('Test', 'echo test')).to eq 'test output'
    end
  end
end
