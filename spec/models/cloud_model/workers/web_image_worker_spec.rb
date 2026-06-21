require 'spec_helper'

describe CloudModel::Workers::WebImageWorker do
  let(:web_image) do
    double 'WebImage',
      id: 'web42',
      name: 'test-app',
      build_path: '/tmp/web_build/web42',
      build_gem_home: '/tmp/web_build/web42/bundle/ruby/3.4.0',
      git_server: 'git@github.com',
      git_repo: 'org/webapp',
      git_branch: 'main',
      build_state: :pending,
      has_assets: false,
      file_id: nil
  end

  subject { CloudModel::Workers::WebImageWorker.new web_image }

  describe 'checkout_git' do
    before do
      allow(File).to receive(:directory?).with(web_image.build_path).and_return(true)
      allow(subject).to receive(:run_with_clean_env).and_return('abc123')
      allow(web_image).to receive(:update_attribute)
      allow(subject).to receive(:puts)
    end

    it 'should pull latest changes when directory exists' do
      expect(subject).to receive(:run_with_clean_env).with("Pulling", /git checkout.*git pull/)
      subject.checkout_git
    end

    it 'should update git_commit attribute' do
      expect(web_image).to receive(:update_attribute).with(:git_commit, 'abc123')
      subject.checkout_git
    end

    it 'should return true on success' do
      expect(subject.checkout_git).to eq true
    end
  end

  describe 'bundle_image' do
    it 'should run bundle install' do
      allow(subject).to receive(:run_with_clean_env)
      expect(subject).to receive(:run_with_clean_env).with("Bundling", /bundle.*install/)
      expect(subject.bundle_image).to eq true
    end

    it 'should return false on failure' do
      allow(subject).to receive(:run_with_clean_env).and_raise(CloudModel::ExecutionException.new('cmd', 'fail', ''))
      allow(CloudModel).to receive(:log_exception)
      allow(web_image).to receive(:update_attributes)
      allow(FileUtils).to receive(:rm_rf)

      expect(subject.bundle_image).to eq false
    end
  end

  describe 'build_assets' do
    it 'should precompile rails assets' do
      allow(FileUtils).to receive(:rm_rf)
      allow(subject).to receive(:run_with_clean_env)
      expect(subject).to receive(:run_with_clean_env).with("Building Assets", /assets:precompile/)
      expect(subject.build_assets).to eq true
    end

    it 'should return false on failure' do
      allow(FileUtils).to receive(:rm_rf)
      allow(subject).to receive(:run_with_clean_env).and_raise(CloudModel::ExecutionException.new('cmd', 'fail', ''))
      allow(CloudModel).to receive(:log_exception)
      allow(web_image).to receive(:update_attributes)

      expect(subject.build_assets).to eq false
    end
  end

  describe 'package_build' do
    it 'should create a tar.bz2 package' do
      allow(subject).to receive(:run_within_build_env)
      allow(FileUtils).to receive(:mv)
      expect(subject).to receive(:run_within_build_env).with("Packaging", /tar -cpjf/)
      expect(subject.package_build).to eq true
    end

    it 'should return false on failure' do
      allow(subject).to receive(:run_within_build_env).and_raise(CloudModel::ExecutionException.new('cmd', 'fail', ''))
      allow(CloudModel).to receive(:log_exception)
      allow(web_image).to receive(:update_attributes)

      expect(subject.package_build).to eq false
    end
  end

  describe 'build' do
    it 'should return false if not pending and not forced' do
      allow(web_image).to receive(:build_state).and_return(:running)
      expect(subject.build).to eq false
    end

    it 'should run full build pipeline when pending' do
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:update_attribute)
      allow(subject).to receive(:checkout_git).and_return(true)
      allow(subject).to receive(:package_build).and_return(true)
      allow(File).to receive(:file?).and_return(false)
      file = double 'GridFsFile', id: 'file123'
      allow(Mongoid::GridFs).to receive(:put).and_return(file)

      expect(web_image).to receive(:update_attributes).with(build_state: :running, build_last_issue: nil)
      expect(web_image).to receive(:update_attributes).with(build_state: :finished)
      expect(subject.build).to eq true
    end
  end
end
