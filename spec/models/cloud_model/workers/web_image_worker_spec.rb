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

    context 'when build directory does not exist' do
      before do
        allow(File).to receive(:directory?).with(web_image.build_path).and_return(false)
        allow(FileUtils).to receive(:mkdir_p).and_return(['/tmp/web_build/web42'])
      end

      it 'should create the directory and clone the repo' do
        expect(FileUtils).to receive(:mkdir_p).with(web_image.build_path).and_return(['/tmp/web_build/web42'])
        expect(subject).to receive(:run_with_clean_env).with("Cloning", /git clone/)
        expect(subject.checkout_git).to eq true
      end

      it 'should fail and clean up when clone raises' do
        allow(FileUtils).to receive(:rm_rf)
        allow(CloudModel).to receive(:log_exception)
        allow(web_image).to receive(:update_attributes)
        allow(subject).to receive(:puts)
        # The rescue in source calls `puts e.trace`, so the exception must respond to #trace.
        clone_error = StandardError.new('boom')
        def clone_error.trace; 'traceback'; end
        allow(subject).to receive(:run_with_clean_env).with("Cloning", anything).and_raise(clone_error)

        expect(web_image).to receive(:update_attributes).with(build_state: :failed, build_last_issue: /Unable to clone/)
        expect(FileUtils).to receive(:rm_rf).with(web_image.build_path)
        expect(subject.checkout_git).to eq false
      end
    end

    it 'should fail when pulling raises an ExecutionException' do
      allow(CloudModel).to receive(:log_exception)
      allow(web_image).to receive(:update_attributes)
      allow(subject).to receive(:run_with_clean_env).with("Pulling", anything).and_raise(CloudModel::ExecutionException.new('cmd', 'fail', ''))

      expect(web_image).to receive(:update_attributes).with(build_state: :failed, build_last_issue: /Unable to checkout branch/)
      expect(subject.checkout_git).to eq false
    end

    it 'should set a fallback commit hash when git log lookup raises' do
      allow(CloudModel).to receive(:log_exception)
      allow(subject).to receive(:run_with_clean_env).with("Pulling", anything).and_return('')
      allow(subject).to receive(:run_with_clean_env).with("Get Version", anything).and_raise(StandardError.new('no git'))

      expect(web_image).to receive(:update_attribute).with(:git_commit, 'failed to get commit hash')
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

  describe 'yarn_install' do
    it 'should install all yarn packages (incl. dev build tooling, not --production)' do
      allow(subject).to receive(:run_with_clean_env)
      # full install (no --production): Vite/Sass build deps are needed to build assets
      expect(subject).to receive(:run_with_clean_env).with("Yarn install", /yarn install --non-interactive --no-bin-links/)
      expect(subject.yarn_install).to eq true
    end

    it 'should return false and clean up on failure' do
      allow(FileUtils).to receive(:rm_rf)
      allow(CloudModel).to receive(:log_exception)
      allow(web_image).to receive(:update_attributes)
      allow(subject).to receive(:run_with_clean_env).and_raise(CloudModel::ExecutionException.new('cmd', 'fail', ''))

      expect(web_image).to receive(:update_attributes).with(build_state: :failed, build_last_issue: 'Unable to install yarn packages.')
      expect(FileUtils).to receive(:rm_rf).with(web_image.build_gem_home)
      expect(subject.yarn_install).to eq false
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

  describe 'prune_node_modules' do
    it 'should reinstall with --production to strip dev build tooling' do
      allow(subject).to receive(:run_with_clean_env)
      expect(subject).to receive(:run_with_clean_env).with("Pruning node modules", /yarn install --production/)
      expect(subject.prune_node_modules).to eq true
    end

    it 'should be non-fatal when pruning fails' do
      allow(subject).to receive(:run_with_clean_env).and_raise(CloudModel::ExecutionException.new('cmd', 'fail', ''))
      allow(CloudModel).to receive(:log_exception)
      expect(subject.prune_node_modules).to eq true
    end
  end

  describe 'package_build' do
    before do
      # the worker writes a tar --exclude-from list into a sibling file
      allow(File).to receive(:write)
      allow(File).to receive(:delete)
    end

    it 'should create a tar.bz2 package using an --exclude-from list' do
      allow(subject).to receive(:run_within_build_env)
      allow(FileUtils).to receive(:mv)
      expect(subject).to receive(:run_within_build_env).with("Packaging", /tar -cpjf .*--exclude-from=\S*web42-package\.excludes /)
      expect(subject.package_build).to eq true
    end

    it 'should write the curated exclude list (rust target excluded, node_modules kept)' do
      allow(subject).to receive(:run_within_build_env)
      allow(FileUtils).to receive(:mv)
      expect(File).to receive(:write).with(
        '/tmp/web_build/web42-package.excludes',
        satisfy { |c| c.include?('*/ext/*/target') and c.include?('./.git') and c.include?('./doc') and !c.include?('node_modules') }
      )
      subject.package_build
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

    it 'should run when forced even if not pending' do
      allow(web_image).to receive(:build_state).and_return(:finished)
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:update_attribute)
      allow(subject).to receive(:checkout_git).and_return(true)
      allow(subject).to receive(:package_build).and_return(true)
      allow(File).to receive(:file?).and_return(false)
      file = double 'GridFsFile', id: 'file123'
      allow(Mongoid::GridFs).to receive(:put).and_return(file)

      expect(subject.build(force: true)).to eq true
    end

    it 'should clean the build path when :clean option is given' do
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:update_attribute)
      allow(subject).to receive(:checkout_git).and_return(true)
      allow(subject).to receive(:package_build).and_return(true)
      allow(File).to receive(:file?).and_return(false)
      allow(Mongoid::GridFs).to receive(:put).and_return(double('GridFsFile', id: 'file123'))
      allow(FileUtils).to receive(:rm_rf)

      expect(FileUtils).to receive(:rm_rf).with(web_image.build_path)
      subject.build(clean: true)
    end

    it 'should run bundle, yarn and assets steps when files/flags present' do
      allow(web_image).to receive(:has_assets).and_return(true)
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:update_attribute)
      allow(subject).to receive(:checkout_git).and_return(true)
      allow(subject).to receive(:package_build).and_return(true)
      allow(File).to receive(:file?).and_return(true)
      allow(Mongoid::GridFs).to receive(:put).and_return(double('GridFsFile', id: 'file123'))

      expect(subject).to receive(:bundle_image).and_return(true)
      expect(subject).to receive(:yarn_install).and_return(true)
      expect(subject).to receive(:build_assets).and_return(true)
      expect(subject).to receive(:prune_node_modules).and_return(true)
      expect(subject.build).to eq true
    end

    it 'should return false when checkout_git fails' do
      allow(web_image).to receive(:update_attributes)
      allow(subject).to receive(:checkout_git).and_return(false)

      expect(subject.build).to eq false
    end

    it 'should delete the old file when replacing the stored image' do
      allow(web_image).to receive(:build_state).and_return(:pending)
      allow(web_image).to receive(:file_id).and_return('old123')
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:update_attribute)
      allow(subject).to receive(:checkout_git).and_return(true)
      allow(subject).to receive(:package_build).and_return(true)
      allow(File).to receive(:file?).and_return(false)
      allow(Mongoid::GridFs).to receive(:put).and_return(double('GridFsFile', id: 'new456'))
      allow(Mongoid::GridFs).to receive(:delete)

      expect(Mongoid::GridFs).to receive(:delete).with('old123')
      subject.build
    end

    it 'should record build_last_issue when storing raises' do
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:update_attribute)
      allow(subject).to receive(:checkout_git).and_return(true)
      allow(subject).to receive(:package_build).and_return(true)
      allow(File).to receive(:file?).and_return(false)
      allow(CloudModel).to receive(:log_exception)
      allow(Mongoid::GridFs).to receive(:put).and_raise(StandardError.new('gridfs down'))

      expect(web_image).to receive(:update_attributes).with(hash_including(build_state: :failed))
      subject.build
    end
  end

  describe 'redeploy' do
    let(:service_a) { double 'ServiceA', redeployable?: true }
    let(:service_b) { double 'ServiceB', redeployable?: false }

    before do
      allow(subject).to receive(:puts)
      allow(web_image).to receive(:redeploy_state).and_return(:pending)
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:services).and_return([service_a, service_b])
      allow(service_a).to receive(:update_attributes)
      allow(service_a).to receive(:redeploy!)
      allow(service_b).to receive(:redeploy!)
    end

    it 'should refuse when not pending and not forced' do
      allow(web_image).to receive(:redeploy_state).and_return(:running)
      expect(subject.redeploy).to eq false
    end

    it 'should mark redeployable services pending and fan out redeploy!' do
      expect(service_a).to receive(:update_attributes).with(redeploy_web_image_state: :pending)
      expect(service_b).not_to receive(:update_attributes)
      expect(service_a).to receive(:redeploy!)
      expect(service_b).to receive(:redeploy!)
      subject.redeploy
    end

    it 'should mark every service pending when forced' do
      allow(service_b).to receive(:update_attributes)
      expect(service_b).to receive(:update_attributes).with(redeploy_web_image_state: :pending)
      subject.redeploy(force: true)
    end

    it 'should set redeploy_state to finished on success' do
      expect(web_image).to receive(:update_attributes).with(redeploy_state: :finished)
      subject.redeploy
    end

    it 'should fail and record issue when a service redeploy raises' do
      allow(CloudModel).to receive(:log_exception)
      allow(service_a).to receive(:redeploy!).and_raise(StandardError.new('deploy broke'))

      expect(web_image).to receive(:update_attributes).with(hash_including(redeploy_state: :failed))
      expect(subject.redeploy).to eq false
    end
  end

  describe 'run_step' do
    before do
      allow(Rails.logger).to receive(:debug)
      allow(Rails.logger).to receive(:error)
    end

    it 'should return command output on success' do
      allow(subject).to receive(:`) { `true`; "all good\n" }
      expect(subject.run_step('Testing', 'echo hi')).to eq "all good\n"
    end

    it 'should raise ExecutionException on non-zero exit' do
      allow(subject).to receive(:`) { `false`; "" }
      expect { subject.run_step('Testing', 'badcmd') }.to raise_error(CloudModel::ExecutionException)
    end
  end

  describe 'run_with_clean_env' do
    it 'should set BUNDLE_GEMFILE and delegate to run_step' do
      # Bundler.with_original_env restores ENV after the block, so assert inside the stub.
      seen = nil
      allow(subject).to receive(:run_step) do |step, cmd|
        seen = ENV['BUNDLE_GEMFILE']
        'ok'
      end
      expect(subject.run_with_clean_env('Step', 'cmd')).to eq 'ok'
      expect(seen).to eq "#{web_image.build_path}/Gemfile"
    end
  end

  describe 'run_within_build_env' do
    it 'should set GEM_HOME and delegate to run_step' do
      seen = nil
      allow(subject).to receive(:run_step) do |step, cmd|
        seen = ENV['GEM_HOME']
        'ok'
      end
      expect(subject.run_within_build_env('Step', 'cmd')).to eq 'ok'
      expect(seen).to eq web_image.build_gem_home
    end
  end
end
