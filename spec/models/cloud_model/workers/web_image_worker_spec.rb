require 'spec_helper'

describe CloudModel::Workers::WebImageWorker do
  let(:host) { double CloudModel::Host, name: 'host23', arch: 'MOS6502', ssh_address: '10.0.0.23' }
  # The shared build environment (a GuestTemplate) cloned as the build system.
  let(:build_env) { double CloudModel::GuestTemplate, id: 'benv', name: 'build-env', build_dataset: 'guests/build/1/benv' }

  let(:web_image) do
    double 'WebImage',
      id: 'web42',
      name: 'test-app',
      build_path: '/tmp/web_build/web42',
      build_dataset: 'guests/build/web/web42/MOS6502',
      build_mountpoint: '/cloud/build/web/web42/MOS6502',
      git_server: 'git@github.com',
      git_repo: 'org/webapp',
      git_branch: 'main',
      build_state: :pending,
      ruby_version: nil,
      has_assets: false
  end

  subject { CloudModel::Workers::WebImageWorker.new host, web_image }

  before do
    allow(web_image).to receive(:build_dataset).with('MOS6502').and_return 'guests/build/web/web42/MOS6502'
    allow(web_image).to receive(:build_mountpoint).with('MOS6502').and_return '/cloud/build/web/web42/MOS6502'
    allow(web_image).to receive(:build_env_template).with(host).and_return build_env
    allow(subject).to receive(:puts)
    allow(subject).to receive(:print)
    allow(subject).to receive(:comment_sub_step)
  end

  describe 'checkout_git (local, keeps github credentials on admin)' do
    before do
      allow(FileUtils).to receive(:mkdir_p)
      allow(File).to receive(:directory?).with("#{web_image.build_path}/.git").and_return(true)
      allow(subject).to receive(:run_with_clean_env).and_return('abc123')
      allow(web_image).to receive(:update_attribute)
    end

    it 'pulls and hard-resets to the remote branch head' do
      expect(subject).to receive(:run_with_clean_env).with("Pulling", /git fetch.*git checkout -f.*git reset --hard/m)
      subject.checkout_git
    end

    it 'records the built commit' do
      expect(web_image).to receive(:update_attribute).with(:git_commit, 'abc123')
      subject.checkout_git
    end

    it 'clones when there is no checkout yet' do
      allow(File).to receive(:directory?).with("#{web_image.build_path}/.git").and_return(false)
      expect(subject).to receive(:run_with_clean_env).with("Cloning", /git clone git@github.com:org\/webapp/)
      subject.checkout_git
    end
  end

  describe 'volume layout' do
    it 'clones a throwaway build system next to the app dataset' do
      subject.instance_variable_set :@arch, 'MOS6502'
      expect(subject.buildsys_volume.dataset_name).to eq 'guests/build/web/web42/MOS6502-buildenv'
    end

    it 'mounts the app volume at the staging path inside the build system' do
      subject.instance_variable_set :@arch, 'MOS6502'
      expect(subject.app_volume.dataset_name).to eq 'guests/build/web/web42/MOS6502'
      expect(subject.app_volume.mountpoint).to end_with described_class::CHROOT_APP_ROOT
    end
  end

  describe 'build_app_volume' do
    let(:app_volume) { double CloudModel::BuildZfsVolume, prepare!: true, mount!: true, unmount!: true, dataset_exists?: false, dataset_name: 'guests/build/web/web42/MOS6502', mountpoint: '/mnt/ws' }
    let(:buildsys_volume) { double CloudModel::BuildZfsVolume, prepare_from!: true, destroy!: true, rootfs_path: '/cloud/build/web/web42/MOS6502-buildenv/rootfs' }

    before do
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:update_attribute)
      allow(web_image).to receive(:record_artifact_size)
      allow(web_image).to receive(:record_artifact_version)
      allow(web_image).to receive(:append_to_build_log)
      allow(build_env).to receive(:ensure_build_volume!)
      allow(host).to receive(:exec!)
      allow(host).to receive(:exec).and_return([true, '123456'])
      allow(subject).to receive(:buildsys_volume).and_return buildsys_volume
      allow(subject).to receive(:app_volume).and_return app_volume
      allow(subject).to receive(:checkout_git)
      allow(subject).to receive(:transfer_source)
      allow(subject).to receive(:configure_git_credentials)
      allow(subject).to receive(:write_bundle_config)
      allow(subject).to receive(:write_puppeteer_config)
      allow(subject).to receive(:cleanup_chroot)
      allow(subject).to receive(:chroot!)
      allow(File).to receive(:file?).and_return(true)
    end

    it 'runs the pipeline, snapshots a version and keeps the workspace' do
      expect(subject).to receive(:checkout_git).ordered
      expect(build_env).to receive(:ensure_build_volume!).with(host).ordered
      expect(buildsys_volume).to receive(:prepare_from!).with('guests/build/1/benv').ordered
      expect(app_volume).to receive(:prepare!).ordered   # first build (dataset_exists? false)
      expect(subject).to receive(:transfer_source).ordered
      expect(subject).to receive(:chroot!).at_least(:once)
      # versioned snapshot, workspace NOT destroyed, only the build system is
      expect(host).to receive(:exec!).with('zfs set mountpoint=none guests/build/web/web42/MOS6502', anything).ordered
      expect(host).to receive(:exec!).with(/zfs snapshot .*web42\/MOS6502@v\d+/, anything).ordered
      expect(web_image).to receive(:record_artifact_version).with('MOS6502', /\A\d{14}\z/)
      expect(buildsys_volume).to receive(:destroy!).ordered
      expect(app_volume).not_to receive(:destroy!)

      expect(subject.build_app_volume('MOS6502')).to eq true
    end

    it 'pins the ruby version before bundling, so RVM bundles on the ruby the artifact runs on' do
      allow(subject).to receive(:chroot!).and_call_original
      allow(subject).to receive(:prepare_chroot)
      allow(subject).to receive(:render_to_remote)
      allow(host).to receive(:sftp).and_return double(remove!: true)
      allow(web_image).to receive(:ruby_version).and_return '3.4.8'

      expect(host).to receive(:exec!).with(/printf %s 3.4.8 > .*\.ruby-version/, anything).ordered
      expect(host).to receive(:exec).with(/chroot .* \/root\/chroot-.*\.sh/).ordered.and_return [true, '']
      allow(host).to receive(:exec!).with(/zfs|cp /, anything)

      subject.build_app_volume('MOS6502')
    end

    it 'reuses an existing workspace incrementally (mount, not wipe)' do
      allow(app_volume).to receive(:dataset_exists?).and_return true
      expect(app_volume).to receive(:mount!)
      expect(app_volume).not_to receive(:prepare!)
      subject.build_app_volume('MOS6502')
    end

    it 'records the artifact size after snapshot — the dataset alone, without snapshots and the cache child' do
      allow(host).to receive(:exec).with('zfs list -H -p -o usedbydataset guests/build/web/web42/MOS6502').and_return([true, "789\n"])
      expect(web_image).to receive(:record_artifact_size).with('MOS6502', 789)
      subject.build_app_volume('MOS6502')
    end

    describe 'build cache (child dataset, never in the artifact)' do
      let(:cache) { 'guests/build/web/web42/MOS6502/.build-cache' }
      let(:cache_path) { '/cloud/build/web/web42/MOS6502-buildenv/rootfs/webimage/.build-cache' }

      it 'creates the cache dataset on the first build and mounts it on every one' do
        allow(host).to receive(:exec).with("zfs list #{cache}").and_return [false, 'does not exist']
        allow(host).to receive(:exec).with("zfs get -H -o value mounted #{cache}").and_return [true, "no\n"]
        expect(host).to receive(:exec!).with(/\Azfs create -p( -o compression=\S+)? #{Regexp.escape cache}\z/, anything).ordered
        expect(host).to receive(:exec!).with("zfs mount #{cache}", anything).ordered
        expect(host).to receive(:exec!).with("mkdir -p #{cache_path}/cargo #{cache_path}/cargo-target #{cache_path}/yarn #{cache_path}/git", anything).ordered

        subject.build_app_volume('MOS6502')
      end

      it 'reuses an existing, mounted cache without touching zfs' do
        allow(host).to receive(:exec).with("zfs list #{cache}").and_return [true, cache]
        allow(host).to receive(:exec).with("zfs get -H -o value mounted #{cache}").and_return [true, "yes\n"]
        expect(host).not_to receive(:exec!).with(/zfs (create|mount) /, anything)

        subject.build_app_volume('MOS6502')
      end

      it 'detaches the cache, strips the workspace and owns it before the snapshot' do
        expect(host).to receive(:exec!).with("zfs unmount #{cache}", anything).ordered
        expect(host).to receive(:exec!).with("rmdir #{cache_path}", anything).ordered
        expect(host).to receive(:exec!).with(/\Acd \/cloud\/build\/web\/web42\/MOS6502-buildenv\/rootfs\/webimage && rm -rf \.git .*bundle\/ruby\/\*\/cache.*ext\/\*\/target/, anything).ordered
        expect(host).to receive(:exec!).with(/\Achown -R 101001:101001 /, anything).ordered
        expect(host).to receive(:exec!).with(/\Azfs snapshot /, anything).ordered

        subject.build_app_volume('MOS6502')
      end

      it 'points the toolchain caches into the cache dataset for bundling and assets' do
        allow(web_image).to receive(:has_assets).and_return true
        expect(subject).to receive(:chroot!).with(anything, /bundle install/, anything) do |_dir, cmd, _msg|
          expect(cmd).to include 'CARGO_HOME=/webimage/.build-cache/cargo'
          expect(cmd).to include 'CARGO_TARGET_DIR=/webimage/.build-cache/cargo-target'
          expect(cmd).to include 'RUSTUP_HOME=/usr/local/rustup'
        end
        expect(subject).to receive(:chroot!).with(anything, /assets:precompile/, anything) do |_dir, cmd, _msg|
          expect(cmd).to include 'CARGO_HOME=/webimage/.build-cache/cargo'
        end
        allow(subject).to receive(:chroot!).with(anything, /ruby -e|yarn install/, anything)

        subject.build_app_volume('MOS6502')
      end

      it 'unmounts the cache before the workspace when a build fails' do
        subject.instance_variable_set :@app_volume, app_volume   # memoized in a real run
        allow(subject).to receive(:bundle_image).and_raise('boom')
        expect(host).to receive(:exec).with("zfs unmount #{cache}").ordered
        expect(app_volume).to receive(:unmount!).ordered

        expect(subject.build_app_volume('MOS6502')).to eq false
      end
    end

    describe 'git dir for the build (transfer_git_dir)' do
      before do
        allow(subject).to receive(:transfer_source).and_call_original
        allow(subject).to receive(:local_exec!)
        allow(CloudModel.config).to receive(:ssh_key_file).and_return '/keys/id_rsa'
      end

      it 'rsyncs .git into the cache dataset and points a gitdir file at it' do
        allow(File).to receive(:directory?).with('/tmp/web_build/web42/.git').and_return true
        # --delete must spare the cache mountpoint, which has no counterpart in the checkout
        expect(subject).to receive(:local_exec!).with(%r{\Arsync -a --delete --exclude=.* --exclude=\.build-cache -e }, anything).ordered
        expect(subject).to receive(:local_exec!).with(%r{\Arsync -a --delete -e .* /tmp/web_build/web42/\.git/ root@10\.0\.0\.23:/cloud/build/web/web42/MOS6502-buildenv/rootfs/webimage/\.build-cache/git/\z}, anything).ordered
        expect(host).to receive(:exec!).with("printf 'gitdir: %s\\n' .build-cache/git > /cloud/build/web/web42/MOS6502-buildenv/rootfs/webimage/.git", anything)
        expect(subject).to receive(:chroot!).with(buildsys_volume.rootfs_path, 'git config --global --add safe.directory /webimage', anything)

        subject.build_app_volume('MOS6502')
      end

      it 'does nothing without a .git in the checkout' do
        allow(File).to receive(:directory?).with('/tmp/web_build/web42/.git').and_return false
        expect(subject).not_to receive(:local_exec!).with(%r{\.git/ root@}, anything)
        expect(host).not_to receive(:exec!).with(/gitdir/, anything)

        subject.build_app_volume('MOS6502')
      end
    end

    it 'marks the image failed and cleans up on error' do
      allow(subject).to receive(:checkout_git).and_raise('boom')
      expect(web_image).to receive(:update_attributes).with(hash_including(build_state: :failed))
      expect(subject).to receive(:cleanup_build_env)
      expect(subject.build_app_volume('MOS6502')).to eq false
    end
  end

  describe 'redeploy (rolls the built artifact out per service)' do
    before do
      allow(web_image).to receive(:redeploy_state).and_return :pending
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:append_to_build_log)
    end

    let(:host_a) { double 'host a', name: 'host-a' }
    let(:host_b) { double 'host b', name: 'host-b' }
    let(:guest_a1) { double 'guest a1', name: 'a1', host_id: 'a', host: host_a }
    let(:guest_a2) { double 'guest a2', name: 'a2', host_id: 'a', host: host_a }
    let(:guest_b1) { double 'guest b1', name: 'b1', host_id: 'b', host: host_b }

    def service guest, ok = true
      double("service #{guest.name}", guest: guest, name: 'Graph', redeployable?: true, update_attributes: true).tap do |s|
        allow(s).to receive(:redeploy!).and_return ok
      end
    end

    before { allow(CloudModel::Guest).to receive(:puts) }

    it 'sets each service pending and redeploys it' do
      s = service guest_a1
      allow(web_image).to receive(:services).and_return [s]
      expect(s).to receive(:update_attributes).with(redeploy_web_image_state: :pending)
      expect(s).to receive(:redeploy!)
      expect(web_image).to receive(:update_attributes).with(redeploy_state: :finished)

      subject.redeploy
    end

    it 'rolls out host by host in parallel, the guests of a host one after another' do
      order = Queue.new
      a1, a2, b1 = service(guest_a1), service(guest_a2), service(guest_b1)
      allow(a1).to receive(:redeploy!) { order << :a1_start; sleep 0.05; order << :a1_end; true }
      allow(a2).to receive(:redeploy!) { order << :a2_start; order << :a2_end; true }
      allow(b1).to receive(:redeploy!) { order << :b1_start; order << :b1_end; true }
      allow(web_image).to receive(:services).and_return [a1, a2, b1]

      subject.redeploy
      seq = []; seq << order.pop until order.empty?
      expect(seq.index(:a1_end)).to be < seq.index(:a2_start)       # same host: sequential
      expect(seq.index(:b1_start)).to be < seq.index(:a1_end)       # other host: in parallel
    end

    it 'goes on after a failed guest and marks the image failed, naming it' do
      a1, b1 = service(guest_a1, false), service(guest_b1)
      allow(web_image).to receive(:services).and_return [a1, b1]
      allow(CloudModel).to receive(:log_exception)
      expect(b1).to receive(:redeploy!).and_return true
      expect(web_image).to receive(:update_attributes).with(redeploy_state: :failed, redeploy_last_issue: /a1: rollout failed: Graph/)

      expect(subject.redeploy).to eq false
    end
  end

  describe 'run_step' do
    it 'raises an ExecutionException when the command fails' do
      allow(subject).to receive(:system)
      expect {
        subject.run_step 'Failing', 'false'
      }.to raise_error(CloudModel::ExecutionException)
    end
  end
end
