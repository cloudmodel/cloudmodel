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

  describe '.unroll_web_image' do
    let(:sftp) {double 'Sftp'}
    let(:web_image) {double 'WebImage', name: 'test-image', id: 'wimg1', file_id: 'gridfs1', file: double('ImageFile', data: 'image_data'), has_mongodb?: false, has_redis?: false, master_key: nil}
    let(:cache_file) { '/var/cache/cloud_model/web_images/wimg1-gridfs1.tar' }

    before do
      allow(model).to receive(:deploy_web_image).and_return(web_image)
      allow(sftp).to receive(:upload!)
      allow(sftp).to receive(:remove!)
      allow(host).to receive(:sftp).and_return(sftp)
      # exec returns [success, stdout]; default to a cache miss (test -f false)
      allow(host).to receive(:exec).and_return([false, ''])
      allow(host).to receive(:exec!)
    end

    it 'should return false if no deploy_web_image' do
      allow(model).to receive(:deploy_web_image).and_return(nil)
      expect(subject.unroll_web_image('/deploy/path')).to eq false
    end

    it 'should create deploy directory' do
      expect(subject).to receive(:mkdir_p).with('/deploy/path')
      subject.unroll_web_image('/deploy/path')
    end

    it 'should load from GridFS and upload to the host cache on a cache miss' do
      expect(sftp).to receive(:upload!).with(instance_of(StringIO), cache_file)
      subject.unroll_web_image('/deploy/path')
    end

    it 'should evict older versions of the same image on a cache miss' do
      expect(host).to receive(:exec).with('rm -f /var/cache/cloud_model/web_images/wimg1-*.tar')
      subject.unroll_web_image('/deploy/path')
    end

    it 'should reuse the host cache without touching GridFS on a cache hit' do
      allow(host).to receive(:exec).with("test -f #{cache_file.shellescape}").and_return([true, ''])
      expect(web_image).not_to receive(:file)
      expect(sftp).not_to receive(:upload!)
      expect(host).to receive(:exec).with(%r{cd /deploy/path && tar xpf #{Regexp.escape(cache_file)}})
      subject.unroll_web_image('/deploy/path')
    end

    it 'should extract the cached tarball to deploy path' do
      expect(host).to receive(:exec).with(%r{cd /deploy/path && tar xpf})
      subject.unroll_web_image('/deploy/path')
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

    it 'should write master key if present' do
      allow(web_image).to receive(:master_key).and_return('secret123')
      expect(host).to receive(:exec!).with("echo -n 'secret123' >/deploy/path/config/master.key", 'Failed to set master key')
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

  describe '.deploy_web_image' do
    let(:web_image) {double 'WebImage', name: 'test-image'}

    before do
      allow(model).to receive(:deploy_web_image).and_return(web_image)
      allow(model).to receive(:www_root).and_return('/var/www')
      allow(subject).to receive(:make_deploy_web_image_id).and_return('20240315103045')
      allow(subject).to receive(:unroll_web_image)
      allow(host).to receive(:exec!)
    end

    it 'should do nothing if no deploy_web_image' do
      allow(model).to receive(:deploy_web_image).and_return(nil)
      expect(subject).not_to receive(:unroll_web_image)
      subject.deploy_web_image
    end

    it 'should unroll web image to timestamped deploy path' do
      expect(subject).to receive(:unroll_web_image).with('/path/to/install/var/www/20240315103045')
      subject.deploy_web_image
    end

    it 'should symlink current to deploy id' do
      expect(host).to receive(:exec!).with('cd /path/to/install/var/www; rm current; ln -s 20240315103045 current', 'Failed to set current')
      subject.deploy_web_image
    end
  end

  describe '.redeploy_web_image' do
    let(:web_image) {double 'WebImage', name: 'test-image'}
    let(:current_lxd_container) {double 'LxdContainer', name: 'test-container'}

    before do
      allow(model).to receive(:deploy_web_image).and_return(web_image)
      allow(model).to receive(:redeploy_web_image_state).and_return(:pending)
      allow(model).to receive(:update_attributes)
      allow(model).to receive(:www_root).and_return('/var/www')
      allow(model).to receive(:id).and_return('abc123')
      allow(model).to receive(:name).and_return('test-service')
      allow(model).to receive(:delayed_jobs_supported).and_return(false)
      allow(model).to receive(:guest).and_return(guest)
      allow(guest).to receive(:name).and_return('test-guest')
      allow(guest).to receive(:current_lxd_container).and_return(current_lxd_container)
      allow(guest).to receive(:exec!)
      allow(guest).to receive(:exec).and_return([true, ''])
      allow(subject).to receive(:make_deploy_web_image_id).and_return('20240315103045')
      allow(subject).to receive(:unroll_web_image)
      allow(host).to receive(:exec!)
      allow(host).to receive(:exec)
    end

    it 'should return false if state is not pending and not forced' do
      allow(model).to receive(:redeploy_web_image_state).and_return(:finished)
      expect(subject.redeploy_web_image).to eq false
    end

    it 'should proceed if forced even when state is not pending' do
      allow(model).to receive(:redeploy_web_image_state).and_return(:finished)
      expect(model).to receive(:update_attributes).with(redeploy_web_image_state: :running, redeploy_web_image_last_issue: nil)
      subject.redeploy_web_image(force: true)
    end

    it 'should set state to running' do
      expect(model).to receive(:update_attributes).with(redeploy_web_image_state: :running, redeploy_web_image_last_issue: nil)
      subject.redeploy_web_image
    end

    it 'should unroll web image to temp path' do
      expect(subject).to receive(:unroll_web_image).with("/tmp/webimage_unroll_abc123/var/www/20240315103045")
      subject.redeploy_web_image
    end

    it 'should transfer unrolled data to guest via tar' do
      expect(host).to receive(:exec!).with("cd /tmp/webimage_unroll_abc123 && tar c . | lxc exec test-container -- /bin/tar x -C / --no-same-owner", 'Failed to transfer files')
      subject.redeploy_web_image
    end

    it 'should set ownership on deployed files' do
      expect(guest).to receive(:exec!).with('/bin/chown -R www:www /var/www/20240315103045', 'Failed to set user to www ')
      subject.redeploy_web_image
    end

    it 'should symlink current to new deploy' do
      expect(guest).to receive(:exec!).with('/bin/rm -f /var/www/current', 'Failed to remove old current')
      expect(guest).to receive(:exec!).with('/bin/ln -s /var/www/20240315103045 /var/www/current', 'Failed to set current')
      subject.redeploy_web_image
    end

    it 'should set state to finished on success' do
      expect(model).to receive(:update_attributes).with(redeploy_web_image_state: :finished)
      subject.redeploy_web_image
    end

    it 'should set state to failed on exception' do
      allow(subject).to receive(:unroll_web_image).and_raise(RuntimeError.new('test error'))
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
      expect(host).to receive(:exec!).with("chown -R 101001:100000 /path/to/install/foo/bar", "failed to set owner for /path/to/install/foo/bar")

      expect(web_app).to receive(:config_files_to_render).and_return(
        'cloud_model/web_apps/test_web_app/foo_bar' => ["/foo/bar",0640, uid: '101001'],
      )
      subject.deploy_web_locations
    end

    it 'should allow to set gid on config files' do
      expect(subject).to receive(:render_to_remote).with(
        "cloud_model/web_apps/test_web_app/foo_bar",
        "/path/to/install/foo/bar", 0640, guest: guest, service: model, web_location: model.web_locations.first, model: web_app)
      expect(host).to receive(:exec!).with("chown -R 100000:101001 /path/to/install/foo/bar", "failed to set owner for /path/to/install/foo/bar")

      expect(web_app).to receive(:config_files_to_render).and_return(
        'cloud_model/web_apps/test_web_app/foo_bar' => ["/foo/bar",0640, gid: '101001'],
      )
      subject.deploy_web_locations
    end

    it 'should allow to set uid and gid on config files' do
      expect(subject).to receive(:render_to_remote).with(
        "cloud_model/web_apps/test_web_app/foo_bar",
        "/path/to/install/foo/bar", 0640, guest: guest, service: model, web_location: model.web_locations.first, model: web_app)
      expect(host).to receive(:exec!).with("chown -R 101020:101001 /path/to/install/foo/bar", "failed to set owner for /path/to/install/foo/bar")

      expect(web_app).to receive(:config_files_to_render).and_return(
        'cloud_model/web_apps/test_web_app/foo_bar' => ["/foo/bar",0640, uid: '101020', gid: '101001'],
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

    it 'should chown overlay path' do
      expect(host).to receive(:exec).with("chown -R 100000:100000 #{subject.overlay_path}")
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
end