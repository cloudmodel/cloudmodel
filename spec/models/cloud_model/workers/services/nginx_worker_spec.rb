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
    pending
  end

  describe '.make_deploy_web_image_id' do
    pending
  end

  describe '.deploy_web_image' do
    pending
  end

  describe '.redeploy_web_image' do
    pending
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

    pending
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
    pending
  end
end