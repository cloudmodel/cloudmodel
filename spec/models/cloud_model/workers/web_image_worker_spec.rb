require 'spec_helper'

describe CloudModel::Workers::WebImageWorker do
  let(:host) { double CloudModel::Host, name: 'host23', arch: 'MOS6502', ssh_address: '10.0.0.23' }
  let(:template) { double CloudModel::GuestTemplate, id: 'tid', name: 'ruby', build_dataset: 'guests/build/1/tid' }

  let(:web_image) do
    double 'WebImage',
      id: 'web42',
      name: 'test-app',
      build_path: '/tmp/web_build/web42',
      build_dataset: 'guests/build/web/web42/tid-MOS6502',
      build_mountpoint: '/cloud/build/web/web42/tid-MOS6502',
      git_server: 'git@github.com',
      git_repo: 'org/webapp',
      git_branch: 'main',
      build_state: :pending,
      has_assets: false
  end

  subject { CloudModel::Workers::WebImageWorker.new host, web_image }

  before do
    allow(web_image).to receive(:build_dataset).with(template, 'MOS6502').and_return 'guests/build/web/web42/tid-MOS6502'
    allow(web_image).to receive(:build_mountpoint).with(template, 'MOS6502').and_return '/cloud/build/web/web42/tid-MOS6502'
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
      subject.instance_variable_set :@template, template
      subject.instance_variable_set :@arch, 'MOS6502'
      expect(subject.buildsys_volume.dataset_name).to eq 'guests/build/web/web42/tid-MOS6502-buildenv'
    end

    it 'mounts the app volume at the staging path inside the build system' do
      subject.instance_variable_set :@template, template
      subject.instance_variable_set :@arch, 'MOS6502'
      expect(subject.app_volume.dataset_name).to eq 'guests/build/web/web42/tid-MOS6502'
      expect(subject.app_volume.mountpoint).to end_with described_class::CHROOT_APP_ROOT
    end
  end

  describe 'build_app_volume' do
    let(:app_volume) { double CloudModel::BuildZfsVolume, prepare!: true, mount!: true, unmount!: true, dataset_exists?: false, dataset_name: 'guests/build/web/web42/tid-MOS6502', mountpoint: '/mnt/ws' }
    let(:buildsys_volume) { double CloudModel::BuildZfsVolume, prepare_from!: true, destroy!: true, rootfs_path: '/cloud/build/web/web42/tid-MOS6502-buildenv/rootfs' }

    before do
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:update_attribute)
      allow(web_image).to receive(:record_artifact_size)
      allow(web_image).to receive(:record_artifact_version)
      allow(template).to receive(:ensure_build_volume!)
      allow(host).to receive(:exec!)
      allow(host).to receive(:exec).and_return([true, '123456'])
      allow(subject).to receive(:buildsys_volume).and_return buildsys_volume
      allow(subject).to receive(:app_volume).and_return app_volume
      allow(subject).to receive(:checkout_git)
      allow(subject).to receive(:transfer_source)
      allow(subject).to receive(:configure_git_credentials)
      allow(subject).to receive(:cleanup_chroot)
      allow(subject).to receive(:chroot!)
      allow(File).to receive(:file?).and_return(true)
    end

    it 'runs the pipeline, snapshots a version and keeps the workspace' do
      expect(subject).to receive(:checkout_git).ordered
      expect(buildsys_volume).to receive(:prepare_from!).with('guests/build/1/tid').ordered
      expect(app_volume).to receive(:prepare!).ordered   # first build (dataset_exists? false)
      expect(subject).to receive(:transfer_source).ordered
      expect(subject).to receive(:chroot!).at_least(:once)
      # versioned snapshot, workspace NOT destroyed, only the build system is
      expect(host).to receive(:exec!).with(/zfs snapshot .*tid-MOS6502@v\d+/, anything).ordered
      expect(web_image).to receive(:record_artifact_version).with(template, 'MOS6502', /\A\d{14}\z/)
      expect(buildsys_volume).to receive(:destroy!).ordered
      expect(app_volume).not_to receive(:destroy!)

      expect(subject.build_app_volume(template, 'MOS6502')).to eq true
    end

    it 'reuses an existing workspace incrementally (mount, not wipe)' do
      allow(app_volume).to receive(:dataset_exists?).and_return true
      expect(app_volume).to receive(:mount!)
      expect(app_volume).not_to receive(:prepare!)
      subject.build_app_volume(template, 'MOS6502')
    end

    it 'records the artifact size after snapshot' do
      allow(host).to receive(:exec).with(/zfs list -H -p -o used/).and_return([true, "789\n"])
      expect(web_image).to receive(:record_artifact_size).with(template, 'MOS6502', 789)
      subject.build_app_volume(template, 'MOS6502')
    end

    it 'marks the image failed and cleans up on error' do
      allow(subject).to receive(:checkout_git).and_raise('boom')
      expect(web_image).to receive(:update_attributes).with(hash_including(build_state: :failed))
      expect(subject).to receive(:cleanup_build_env)
      expect(subject.build_app_volume(template, 'MOS6502')).to eq false
    end
  end

  describe 'redeploy (rolls the built artifact out per service)' do
    before do
      allow(web_image).to receive(:redeploy_state).and_return :pending
      allow(web_image).to receive(:update_attributes)
      allow(web_image).to receive(:append_to_build_log)
    end

    it 'sets each service pending and redeploys it' do
      service = double 'service', redeployable?: true
      allow(web_image).to receive(:services).and_return [service]
      expect(service).to receive(:update_attributes).with(redeploy_web_image_state: :pending)
      expect(service).to receive(:redeploy!)

      subject.redeploy
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
