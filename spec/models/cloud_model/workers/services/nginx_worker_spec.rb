require 'spec_helper'

describe CloudModel::Workers::Services::NginxWorker do
  let(:host) {CloudModel::Host.new}
  let(:guest) {CloudModel::Guest.new host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Nginx.new guest: guest}
  subject {CloudModel::Workers::Services::NginxWorker.new lxc, model}

  before do
    allow(guest).to receive(:deploy_path).and_return('/path/to/install')
    allow(host).to receive(:sftp)
    allow(host).to receive(:exec)
    allow(host).to receive(:ssh_connection)
    allow(subject).to receive(:render_to_remote)
    allow(subject).to receive(:chroot)
    allow(subject).to receive(:chroot!)
    allow(subject).to receive(:mkdir_p)
    allow(subject).to receive(:comment_sub_step)
  end

  describe 'restart_rake_daemons' do
    it 'restarts the daemon-mode rake services after a rollout and leaves timer tasks alone' do
      daemon = CloudModel::Services::Rake.new(name: 'Index Worker', rake_task: 'coreon:index_sync', rake_mode: 'restart')
      timer = CloudModel::Services::Rake.new(name: 'Cleanup', rake_task: 'maintenance:cleanup', rake_mode: 'timer')
      allow(guest).to receive(:services).and_return [model, daemon, timer]
      expect(guest).to receive(:exec).with('/bin/systemctl restart rake-coreon:index_sync.service').and_return [true, '']
      expect(guest).not_to receive(:exec).with(/maintenance:cleanup/)

      subject.restart_rake_daemons
    end

    it 'reports a failed restart and goes on' do
      daemon = CloudModel::Services::Rake.new(name: 'Index Worker', rake_task: 'coreon:index_sync', rake_mode: 'restart')
      allow(guest).to receive(:services).and_return [daemon]
      allow(guest).to receive(:exec).and_return [false, 'Unit not found']
      expect { subject.restart_rake_daemons }.to output(/Error restarting rake daemon coreon:index_sync: Unit not found/).to_stdout
    end
  end

  describe '.unroll_web_image (layers instance config onto the cloned artifact)' do
    let(:web_image) {double 'WebImage', name: 'test-image', id: 'wimg1', has_mongodb?: false, has_redis?: false, master_key: nil}

    before do
      allow(model).to receive(:deploy_web_image).and_return(web_image)
      allow(host).to receive(:exec)
      allow(host).to receive(:exec!)
    end

    it 'should return false if no deploy_web_image' do
      allow(model).to receive(:deploy_web_image).and_return(nil)
      expect(subject.unroll_web_image('/deploy/path')).to eq false
    end

    it 'should create config directory' do
      expect(subject).to receive(:mkdir_p).with('/deploy/path/config')
      subject.unroll_web_image('/deploy/path')
    end

    it 'should render mongoid.yml if web image has mongodb' do
      allow(web_image).to receive(:has_mongodb?).and_return(true)
      expect(subject).to receive(:render_to_remote).with('/cloud_model/web_image/mongoid.yml', '/deploy/path/config/mongoid.yml', guest: guest, model: model)
      subject.unroll_web_image('/deploy/path')
    end

    it 'should render redis.yml if web image has redis' do
      allow(web_image).to receive(:has_redis?).and_return(true)
      allow(model).to receive(:deploy_redis_sentinel_set).and_return(nil)
      expect(subject).to receive(:render_to_remote).with('/cloud_model/web_image/redis.yml', '/deploy/path/config/redis.yml', guest: guest, model: model)
      subject.unroll_web_image('/deploy/path')
    end

    it 'should render sentinel.yml if web image has redis with sentinel set' do
      allow(web_image).to receive(:has_redis?).and_return(true)
      allow(model).to receive(:deploy_redis_sentinel_set).and_return(double('SentinelSet'))
      expect(subject).to receive(:render_to_remote).with('/cloud_model/web_image/sentinel.yml', '/deploy/path/config/redis.yml', guest: guest, model: model)
      subject.unroll_web_image('/deploy/path')
    end

    it 'should write the master key over sftp so it never shows up in a logged command' do
      allow(web_image).to receive(:master_key).and_return('secret123')
      sftp_file = double 'sftp_file'
      file_handle = double 'file_handle'
      allow(host).to receive(:sftp).and_return(double('sftp', file: sftp_file))
      expect(sftp_file).to receive(:open).with('/deploy/path/config/master.key', 'w').and_yield(file_handle)
      expect(file_handle).to receive(:write).with('secret123')
      expect(host).not_to receive(:exec!).with(/secret123/, anything)
      expect(host).to receive(:exec!).with('chmod 600 /deploy/path/config/master.key', 'Failed to protect master key')
      subject.unroll_web_image('/deploy/path')
    end

    it 'should create tmp directory and touch restart.txt' do
      expect(subject).to receive(:mkdir_p).with('/deploy/path/tmp')
      expect(host).to receive(:exec).with('touch /deploy/path/tmp/restart.txt')
      subject.unroll_web_image('/deploy/path')
    end
  end

  describe '.make_deploy_web_image_id' do
    it 'should return a timestamp string' do
      expect(subject.make_deploy_web_image_id).to match(/\A\d{14}\z/)
    end

    it 'should return current UTC time formatted as YYYYMMDDHHmmSS' do
      freeze_time = Time.utc(2024, 3, 15, 10, 30, 45)
      allow(Time).to receive(:now).and_return(freeze_time)
      expect(subject.make_deploy_web_image_id).to eq '20240315103045'
    end
  end

  describe '.cleanup_old_web_releases' do
    let(:zfs_list) do
      [
        'guests/web',
        'guests/web/test-guest-20260101000000',
        'guests/web/test-guest-20260102000000',
        'guests/web/test-guest-20260103000000',
        'guests/web/test-guest-20260104000000',
        'guests/web/other-guest-20260101000000'
      ].join("\n")
    end

    before do
      guest.name = 'test-guest'
      allow(host).to receive(:exec).with('zfs list -H -o name -r guests/web').and_return([true, zfs_list])
    end

    it 'should destroy all but the newest KEPT_WEB_RELEASES clones' do
      expect(host).to receive(:exec).with('zfs destroy -r guests/web/test-guest-20260101000000')
      subject.cleanup_old_web_releases '20260104000000', online: false
    end

    it 'should not touch kept releases or other guests\' clones' do
      expect(host).not_to receive(:exec).with(/zfs destroy -r guests\/web\/test-guest-2026010[234]/)
      expect(host).not_to receive(:exec).with(/other-guest/)
      subject.cleanup_old_web_releases '20260104000000', online: false
    end

    it 'should always keep the current release even when older than the newest ones' do
      expect(host).not_to receive(:exec).with(/zfs destroy/)
      subject.cleanup_old_web_releases '20260101000000', online: false
    end

    it 'should remove only devices of destroyed releases when online' do
      allow(lxc).to receive(:name).and_return('test-container')
      allow(host).to receive(:exec).with('lxc config device list test-container')
        .and_return([true, "webapp-20260101000000\nwebapp-20260104000000\nroot\n"])
      expect(host).to receive(:exec).with('lxc config device remove test-container webapp-20260101000000')
      expect(host).not_to receive(:exec).with('lxc config device remove test-container webapp-20260104000000')
      subject.cleanup_old_web_releases '20260104000000', online: true
    end

    it 'should do nothing when the zfs list fails' do
      allow(host).to receive(:exec).with('zfs list -H -o name -r guests/web').and_return([false, ''])
      expect(host).not_to receive(:exec).with(/zfs destroy/)
      subject.cleanup_old_web_releases '20260104000000', online: false
    end
  end

  describe '.provision_web_volume' do
    let(:web_image) {double 'WebImage', name: 'test-image', build_last_issue: 'bundle install failed'}

    before do
      allow(model).to receive(:deploy_web_image).and_return(web_image)
      allow(host).to receive(:arch).and_return('amd64')
      allow(host).to receive(:name).and_return('host23')
      allow(guest).to receive(:name).and_return('test-guest')
    end

    it 'should fail with the build issue instead of cloning a missing artifact' do
      allow(web_image).to receive(:ensure_web_volume!).with(host, 'amd64').and_return(false)
      expect(host).not_to receive(:exec!).with(/zfs clone/, anything)

      expect { subject.provision_web_volume online: true }.to raise_error(/No amd64 artifact of web image test-image on host23: bundle install failed/)
    end

    it 'should fail when the image claims success but has no snapshot for the arch' do
      allow(web_image).to receive(:ensure_web_volume!).and_return(true)
      allow(web_image).to receive(:build_snapshot).with('amd64').and_return(nil)

      expect { subject.provision_web_volume online: true }.to raise_error(/No amd64 artifact/)
    end

    it 'should remove a leftover release clone with a proper error message' do
      allow(web_image).to receive(:ensure_web_volume!).and_return(true)
      allow(web_image).to receive(:build_snapshot).with('amd64').and_return('guests/build/web/img1/amd64@v1')
      allow(subject).to receive(:make_deploy_web_image_id).and_return('20260101000000')
      allow(host).to receive(:exec).with('zfs list guests/web/test-guest-20260101000000').and_return([true, 'exists'])
      allow(host).to receive(:exec!)
      allow(subject).to receive(:unroll_web_image)
      allow(subject).to receive(:ensure_web_release_owner)
      allow(subject).to receive(:own_web_release_config)
      allow(subject).to receive(:attach_web_release)
      allow(subject).to receive(:activate_web_release)
      allow(subject).to receive(:cleanup_old_web_releases)

      expect(host).to receive(:exec!).with('zfs destroy -r guests/web/test-guest-20260101000000', 'Failed to remove leftover release clone guests/web/test-guest-20260101000000')

      subject.provision_web_volume online: true
    end

    it 'should drop chroot submounts before attaching to a stopped container (LXD remounts the volume)' do
      allow(web_image).to receive(:ensure_web_volume!).and_return(true)
      allow(web_image).to receive(:build_snapshot).with('amd64').and_return('guests/build/web/img1/amd64@v1')
      allow(host).to receive(:exec).and_return([false, ''])
      allow(host).to receive(:exec!)
      %i(unroll_web_image ensure_web_release_owner own_web_release_config cleanup_old_web_releases).each { |m| allow(subject).to receive(m) }
      expect(subject).to receive(:cleanup_chroot).with('/path/to/install').ordered
      expect(subject).to receive(:attach_web_release).ordered
      # LXD may have unmounted the volume while rewriting backup.yaml
      expect(lxc).to receive(:mount).ordered
      expect(subject).to receive(:activate_web_release).ordered

      subject.provision_web_volume online: false
    end

    it 'should not touch chroot mounts on a live rollout' do
      allow(web_image).to receive(:ensure_web_volume!).and_return(true)
      allow(web_image).to receive(:build_snapshot).with('amd64').and_return('guests/build/web/img1/amd64@v1')
      allow(host).to receive(:exec).and_return([false, ''])
      allow(host).to receive(:exec!)
      %i(unroll_web_image ensure_web_release_owner own_web_release_config attach_web_release activate_web_release cleanup_old_web_releases).each { |m| allow(subject).to receive(m) }
      expect(subject).not_to receive(:cleanup_chroot)
      expect(lxc).not_to receive(:mount)

      subject.provision_web_volume online: true
    end
  end

  describe '.own_web_release_config' do
    before do
      allow(lxc).to receive(:detect_idmap_base!)
      allow(lxc).to receive(:host_uid).with(1001).and_return(101001)
    end

    it 'should re-read the container´s idmap once before using it' do
      expect(lxc).to receive(:detect_idmap_base!).once
      allow(host).to receive(:exec!)
      subject.own_web_release_config '/cloud/web/g-1'
      subject.own_web_release_config '/cloud/web/g-1'
    end

    it 'should own only the config paths written per guest, as www through the container´s idmap' do
      expect(host).to receive(:exec!).with(
        'for p in /cloud/web/g-1/config /cloud/web/g-1/tmp; do if [ -e "$p" ]; then chown -R 101001:101001 "$p" || exit 1; fi; done',
        'Failed to own web app config'
      )
      subject.own_web_release_config '/cloud/web/g-1'
    end
  end

  describe '.ensure_web_release_owner' do
    before do
      allow(lxc).to receive(:detect_idmap_base!)
      allow(lxc).to receive(:host_uid).with(1001).and_return(101001)
    end

    it 'should not touch a clone already owned through the expected idmap' do
      allow(host).to receive(:exec).with('stat -c %u /cloud/web/g-1').and_return([true, "101001\n"])
      expect(host).not_to receive(:exec!).with(/chown -R/, anything)
      subject.ensure_web_release_owner '/cloud/web/g-1'
    end

    it 'should re-own the whole clone once when the container maps www elsewhere' do
      allow(lxc).to receive(:host_uid).with(1001).and_return(1001001)
      allow(lxc).to receive(:idmap_base).and_return(1000000)
      allow(host).to receive(:exec).with('stat -c %u /cloud/web/g-1').and_return([true, "101001\n"])
      expect(host).to receive(:exec!).with('chown -R 1001001:1001001 /cloud/web/g-1', 'Failed to own web app volume')
      subject.ensure_web_release_owner '/cloud/web/g-1'
    end
  end

  describe '.deploy_web_image' do
    let(:web_image) {double 'WebImage', name: 'test-image'}

    before do
      allow(model).to receive(:deploy_web_image).and_return(web_image)
      allow(subject).to receive(:provision_web_volume)
    end

    it 'should do nothing if no deploy_web_image' do
      allow(model).to receive(:deploy_web_image).and_return(nil)
      expect(subject).not_to receive(:provision_web_volume)
      subject.deploy_web_image
    end

    it 'should provision the web volume offline (into the rootfs)' do
      expect(subject).to receive(:provision_web_volume).with(online: false)
      subject.deploy_web_image
    end
  end

  describe '.redeploy_web_image (clone + Capistrano-style symlink handover)' do
    let(:web_image) {double 'WebImage', name: 'test-image'}

    before do
      allow(model).to receive(:deploy_web_image).and_return(web_image)
      allow(model).to receive(:redeploy_web_image_state).and_return(:pending)
      allow(model).to receive(:update_attributes)
      allow(model).to receive(:update_attribute)
      allow(model).to receive(:www_root).and_return('/var/www/rails')
      allow(model).to receive(:delayed_jobs_supported).and_return(false)
      allow(model).to receive(:guest).and_return(guest)
      allow(guest).to receive(:name).and_return('test-guest')
      allow(guest).to receive(:host).and_return(host)
      allow(host).to receive(:name).and_return('host23')
      allow(guest).to receive(:exec!)
      allow(guest).to receive(:exec).and_return([true, ''])
      allow(web_image).to receive(:append_to_build_log)
      allow(subject).to receive(:provision_web_volume)
      allow(guest).to receive(:template_volume_layout?).with(detect: true).and_return(true)
    end

    it 'should return false if state is not pending and not forced' do
      allow(model).to receive(:redeploy_web_image_state).and_return(:finished)
      expect(subject.redeploy_web_image).to eq false
    end

    context 'on a guest still running the image-based container layout' do
      before do
        allow(guest).to receive(:template_volume_layout?).with(detect: true).and_return(false)
        allow(guest).to receive(:legacy_layout?).and_return(true)
      end

      it 'should refuse the rollout and ask for a guest redeploy instead' do
        expect(model).to receive(:update_attributes).with(
          redeploy_web_image_state: :guest_redeploy_required,
          redeploy_web_image_last_issue: /full guest redeploy is required once/,
          redeploy_web_image_step: nil
        )
        expect(subject).not_to receive(:provision_web_volume)
        expect(guest).not_to receive(:exec)

        expect(subject.redeploy_web_image).to eq false
      end

      it 'should note the skip in the web image build log' do
        expect(web_image).to receive(:append_to_build_log).with(/SKIPPED test-guest: Guest test-guest still runs the image-based container layout/)
        subject.redeploy_web_image
      end

      it 'should refuse even when forced — the layout can not be worked around' do
        expect(subject).not_to receive(:provision_web_volume)
        expect(subject.redeploy_web_image(force: true)).to eq false
      end
    end

    context 'on a guest whose container layout can not be determined' do
      before do
        allow(guest).to receive(:template_volume_layout?).with(detect: true).and_return(false)
        allow(guest).to receive(:legacy_layout?).and_return(false)
      end

      it 'should refuse the rollout rather than guess' do
        expect(model).to receive(:update_attributes).with(
          redeploy_web_image_state: :guest_redeploy_required,
          redeploy_web_image_last_issue: /Could not determine the container layout/,
          redeploy_web_image_step: nil
        )
        expect(subject.redeploy_web_image).to eq false
      end
    end

    it 'should proceed if forced even when state is not pending' do
      allow(model).to receive(:redeploy_web_image_state).and_return(:finished)
      expect(model).to receive(:update_attributes).with(redeploy_web_image_state: :running, redeploy_web_image_last_issue: nil, redeploy_web_image_step: 'transfer')
      subject.redeploy_web_image(force: true)
    end

    it 'should set state to running' do
      expect(model).to receive(:update_attributes).with(redeploy_web_image_state: :running, redeploy_web_image_last_issue: nil, redeploy_web_image_step: 'transfer')
      subject.redeploy_web_image
    end

    it 'should provision a new release online' do
      expect(subject).to receive(:provision_web_volume).with(online: true)
      subject.redeploy_web_image
    end

    it 'should restart the passenger app after the handover' do
      expect(guest).to receive(:exec).with(/passenger-config restart-app/).and_return([true, ''])
      subject.redeploy_web_image
    end

    it 'should set state to finished on success' do
      expect(model).to receive(:update_attributes).with(redeploy_web_image_state: :finished, redeploy_web_image_step: 'done')
      subject.redeploy_web_image
    end

    it 'should set state to failed on exception' do
      allow(subject).to receive(:provision_web_volume).and_raise(RuntimeError.new('test error'))
      allow(CloudModel).to receive(:log_exception)
      expect(model).to receive(:update_attributes).with(redeploy_web_image_state: :failed, redeploy_web_image_last_issue: 'test error')
      subject.redeploy_web_image
    end
  end

  describe '.deploy_web_locations' do
    class TestWebApp < CloudModel::WebApp
    end

    let(:web_app) { TestWebApp.new }

    before do
      allow(guest).to receive(:deploy_path).and_return('/path/to/install')
      model.web_locations.new web_app: web_app
    end

    # @model.web_locations.each do |web_location|
    #   comment_sub_step "Deploy #{web_location.web_app.to_s}"
    #   increase_indent
    #
    #   mkdir_p "#{@guest.deploy_path}/opt/web-app"
    #
    #   web_app = web_location.web_app
    #   web_app_class = web_app.class
    #
    #   # TODO: Fetch/Config per location; For now it only supports one instance of WebApp per Guest
    #   if app_folder = web_app_class.app_folder
    #     if fetch_command = web_app_class.fetch_app_command
    #       comment_sub_step "Fetch #{web_app_class.app_name}"
    #       chroot! @guest.deploy_path, fetch_command, "Failed to download #{web_app_class.app_name}"
    #     end
    #   end
    #
    #   # Systemd Config
    #   # TODO: Render init db user script + systemd prestart if exists
    #   # TODO: Call app init db script on systemd prestart if exists
    #   # TODO: Make and populate persistant folders on systemd prestart
    #
    #   # Render nginx conf if exists
    #   mkdir_p "#{@guest.deploy_path}/etc/nginx/server.d"
    #   if template_exists?("/#{web_app_class.name.underscore}/nginx.conf")
    #     comment_sub_step "Render app nginx.conf"
    #     render_to_remote "/#{web_app_class.name.underscore}/nginx.conf", "#{@guest.deploy_path}/etc/nginx/server.d/#{web_app_class.app_name}-#{web_app.name.underscore.gsub(' ', '_')}.conf", guest: @guest, service: @model, model: web_location
    #   end
    #
    #   # Render config files
    #   web_app.config_files_to_render.each do |src, dst|
    #     comment_sub_step "Render config #{src}"
    #     remote_file = "#{@guest.deploy_path}#{dst[0]}"
    #     render_to_remote src, remote_file, dst[1], guest: @guest, service: @model, web_location: web_location, model: web_app
    #     if dst[2]
    #       uid = dst[2][:uid] || 100000
    #       gid = dst[2][:gid] || 100000
    #       host.exec! "chown -R #{uid}:#{gid} #{remote_file}", "failed to set owner for #{remote_file}"
    #     end
    #   end
    #
    #   decrease_indent
    # end

    it 'should make sure /opt/web-app exists' do
      expect(subject).to receive(:mkdir_p).with('/path/to/install/opt/web-app').and_return true
      subject.deploy_web_locations
    end

    it 'should make sure /etc/nginx/server.d exists' do
      expect(subject).to receive(:mkdir_p).with('/path/to/install/etc/nginx/server.d').and_return true
      subject.deploy_web_locations
    end

    it 'should install web app if it has a fetch command' do
      expect(TestWebApp).to receive(:fetch_app_command).and_return ("#!/bin/test\ntest()")
      expect(subject).to receive(:chroot!).with "/path/to/install", "#!/bin/test\ntest()", "Failed to download test"
      subject.deploy_web_locations
    end

    it 'should render nginx config if app has one' do
      web_app.name = 'Some Name'

      expect(subject).to receive(:template_exists?).with("/test_web_app/nginx.conf").and_return true
      expect(subject).to receive(:render_to_remote).with(
        "/test_web_app/nginx.conf",
        "/path/to/install/etc/nginx/server.d/test-some_name.conf", guest: guest, service: model, model: model.web_locations.first)
      subject.deploy_web_locations
    end

    it 'should render config files if app has some' do
      expect(subject).to receive(:render_to_remote).with(
        "cloud_model/web_apps/test_web_app/config.php",
        "/path/to/install/opt/web-app/test/config.php", 0644, guest: guest, service: model, web_location: model.web_locations.first, model: web_app)
      expect(subject).to receive(:render_to_remote).with(
        "cloud_model/web_apps/test_web_app/foo_bar",
        "/path/to/install/foo/bar", 0640, guest: guest, service: model, web_location: model.web_locations.first, model: web_app)

      expect(web_app).to receive(:config_files_to_render).and_return(
        'cloud_model/web_apps/test_web_app/config.php' => ["/opt/web-app/test/config.php", 0644],
        'cloud_model/web_apps/test_web_app/foo_bar' => ["/foo/bar",0640],
      )
      subject.deploy_web_locations
    end

    it 'should allow to set uid on config files' do
      expect(subject).to receive(:render_to_remote).with(
        "cloud_model/web_apps/test_web_app/foo_bar",
        "/path/to/install/foo/bar", 0640, guest: guest, service: model, web_location: model.web_locations.first, model: web_app)
      # container ids, as the unshifted rootfs needs them
      expect(host).to receive(:exec!).with("chown -R 1001:0 /path/to/install/foo/bar", "failed to set owner for /path/to/install/foo/bar")

      expect(web_app).to receive(:config_files_to_render).and_return(
        'cloud_model/web_apps/test_web_app/foo_bar' => ["/foo/bar",0640, uid: 1001],
      )
      subject.deploy_web_locations
    end

    it 'should allow to set gid on config files' do
      expect(subject).to receive(:render_to_remote).with(
        "cloud_model/web_apps/test_web_app/foo_bar",
        "/path/to/install/foo/bar", 0640, guest: guest, service: model, web_location: model.web_locations.first, model: web_app)
      expect(host).to receive(:exec!).with("chown -R 0:1001 /path/to/install/foo/bar", "failed to set owner for /path/to/install/foo/bar")

      expect(web_app).to receive(:config_files_to_render).and_return(
        'cloud_model/web_apps/test_web_app/foo_bar' => ["/foo/bar",0640, gid: 1001],
      )
      subject.deploy_web_locations
    end

    it 'should allow to set uid and gid on config files' do
      expect(subject).to receive(:render_to_remote).with(
        "cloud_model/web_apps/test_web_app/foo_bar",
        "/path/to/install/foo/bar", 0640, guest: guest, service: model, web_location: model.web_locations.first, model: web_app)
      expect(host).to receive(:exec!).with("chown -R 1020:1001 /path/to/install/foo/bar", "failed to set owner for /path/to/install/foo/bar")

      expect(web_app).to receive(:config_files_to_render).and_return(
        'cloud_model/web_apps/test_web_app/foo_bar' => ["/foo/bar",0640, uid: 1020, gid: 1001],
      )
      subject.deploy_web_locations
    end
  end

  describe '.write_config' do
    before do
      allow(guest).to receive(:deploy_path).and_return "/var/www/rails/#{Time.now.to_i}"
      allow(subject).to receive(:render_to_guest)
    end

    it "should not link delayed jobs service by default" do
      expect(subject).not_to receive(:chroot!).with(guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs@.service /etc/systemd/system/multi-user.target.wants/delayed_jobs@default.service", "Failed to enable delayed_jobs service for queue default")
      subject.write_config
    end

    it "should link delayed jobs service for queue default if delayed_jobs_supported" do
      model.delayed_jobs_supported = true
      expect(subject).to receive(:chroot!).with(guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs@.service /etc/systemd/system/multi-user.target.wants/delayed_jobs@default.service", "Failed to enable delayed_jobs service for queue default")
      subject.write_config
    end

    it "should link delayed jobs service for given queues only if delayed_jobs_supported" do
      model.delayed_jobs_supported = true
      model.delayed_jobs_queues = ['foo', 'bar']
      expect(subject).not_to receive(:chroot!).with(guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs@.service /etc/systemd/system/multi-user.target.wants/delayed_jobs@default.service", "Failed to enable delayed_jobs service for queue default")
      expect(subject).to receive(:chroot!).with(guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs@.service /etc/systemd/system/multi-user.target.wants/delayed_jobs@foo.service", "Failed to enable delayed_jobs service for queue foo")
      expect(subject).to receive(:chroot!).with(guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs@.service /etc/systemd/system/multi-user.target.wants/delayed_jobs@bar.service", "Failed to enable delayed_jobs service for queue bar")
      subject.write_config
    end

    it "should escape queue names" do
      model.delayed_jobs_supported = true
      model.delayed_jobs_queues = ['foo/bar']
      expect(subject).not_to receive(:chroot!).with(guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs@.service /etc/systemd/system/multi-user.target.wants/delayed_jobs@default.service", "Failed to enable delayed_jobs service for queue default")
      expect(subject).to receive(:chroot!).with(guest.deploy_path, "ln -s /etc/systemd/system/delayed_jobs@.service /etc/systemd/system/multi-user.target.wants/delayed_jobs@foo\/bar.service", "Failed to enable delayed_jobs service for queue foo/bar")
      subject.write_config
    end

    it 'should render nginx.conf' do
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/nginx/nginx.conf', '/etc/nginx/nginx.conf', 0600, guest: guest, model: model)
      subject.write_config
    end

    it 'should render cloudmodel.conf' do
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/nginx/sites-available/cloudmodel.conf', '/etc/nginx/sites-available/cloudmodel.conf', 0600, guest: guest, model: model)
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/logrotate.d/nginx', '/etc/logrotate.d/nginx', 0644, guest: guest, model: model)
      subject.write_config
    end

    it 'should create www user' do
      expect(subject).to receive(:chroot!).with(guest.deploy_path, "groupadd -f -r -g 1001 www && id -u www || useradd -c 'added by cloud_model for nginx' -d /var/www -s /bin/bash -r -g 1001 -u 1001 www", "Failed to add www user")
      subject.write_config
    end

    it 'should call deploy_web_image' do
      expect(subject).to receive(:deploy_web_image)
      subject.write_config
    end

    it 'should call deploy_web_locations' do
      expect(subject).to receive(:deploy_web_locations)
      subject.write_config
    end
  end

  describe '.service_name' do
    it 'should return nginx' do
      expect(subject.service_name).to eq 'nginx'
    end
  end

  describe '.auto_restart' do
    it 'should return true' do
      expect(subject.auto_restart).to eq true
    end
  end

  describe '.auto_start' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/path/to/install')
      allow(host).to receive(:exec)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
    end

    it 'should create overlay directory' do
      expect(subject).to receive(:mkdir_p).with(subject.overlay_path)
      subject.auto_start
    end

    it 'should render fix_perms.conf drop-in' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/nginx.service.d/fix_perms.conf', "#{subject.overlay_path}/fix_perms.conf", 644, guest: guest, model: model)
      subject.auto_start
    end

    it 'should leave the overlay root-owned (unshifted rootfs)' do
      expect(host).not_to receive(:exec).with(/chown/)
      subject.auto_start
    end

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/nginx.service /path/to/install/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should write restart drop-in since auto_restart is true' do
      expect(subject).to receive(:render_to_remote).with("/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{subject.overlay_path}/restart.conf", 644)
      subject.auto_start
    end
  end
  describe '#deploy_logrotate_config' do
    let(:lr_guest) { double 'guest', host: double('host'), name: 'web01' }
    let(:lr_lxc) { double 'lxc', guest: lr_guest, name: 'web01-c1' }
    let(:lr_worker) { described_class.new lr_lxc, CloudModel::Services::Nginx.new }

    before do
      allow(lr_worker).to receive(:render).with('/cloud_model/guest/etc/logrotate.d/nginx', guest: lr_guest, model: anything).and_return "rules\n"
      allow(lr_worker).to receive(:upload_to_guest)
    end

    it 'uploads the rules, verifies them with a dry run and clears a failed logrotate unit' do
      expect(lr_worker).to receive(:upload_to_guest).with("rules\n", '/etc/logrotate.d/nginx', '0644')
      expect(lr_guest).to receive(:exec).with('logrotate -d /etc/logrotate.d/nginx').and_return [true, "reading config file /etc/logrotate.d/nginx\nrotating pattern: /var/log/nginx/*.log\n"]
      expect(lr_guest).to receive(:exec).with('systemctl reset-failed logrotate.service')
      expect(lr_worker.deploy_logrotate_config).to eq true
    end

    it 'reports rules logrotate rejects and leaves the failed unit alone' do
      expect(lr_guest).to receive(:exec).with('logrotate -d /etc/logrotate.d/nginx').and_return [true, "error: skipping \"/var/log/nginx/access.log\" because parent directory has insecure permissions\n"]
      expect(lr_guest).not_to receive(:exec).with('systemctl reset-failed logrotate.service')
      expect(lr_worker.deploy_logrotate_config).to eq false
    end
  end

end