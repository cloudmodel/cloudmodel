require 'spec_helper'

describe CloudModel::Workers::Services::TomcatWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Tomcat.new}
  subject {CloudModel::Workers::Services::TomcatWorker.new lxc, model}

  describe 'write_config' do
    let(:sftp) {double 'Sftp'}
    let(:sftp_file) {double 'SftpFile'}
    let(:war_image) {double 'WarImage', name: 'test-war', file: double('WarFile', data: 'war_data')}

    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(host).to receive(:sftp).and_return(sftp)
      allow(host).to receive(:exec)
      allow(host).to receive(:exec!)
      allow(model).to receive(:deploy_war_image).and_return(war_image)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:chroot)
      allow(subject).to receive(:chroot!)
      allow(sftp).to receive(:upload!)
      allow(sftp).to receive(:remove!)
      allow(sftp).to receive(:file).and_return(sftp_file)
      allow(sftp_file).to receive(:open).and_yield(double('file', read: {}.to_yaml))
    end

    it 'should comment deploying war image' do
      expect(subject).to receive(:comment_sub_step).with("Deploy WAR Image test-war to /var/lib/lxc/test/rootfs/var/lib/lxc/test/rootfs/var/tomcat")
      subject.write_config
    end

    it 'should upload war image tarball' do
      expect(sftp).to receive(:upload!).with(instance_of(StringIO), anything)
      subject.write_config
    end

    it 'should extract war image' do
      expect(host).to receive(:exec).with(%r{cd /var/lib/lxc/test/rootfs/var/tomcat.* && tar xjpf})
      subject.write_config
    end

    it 'should read manifest from war image' do
      expect(sftp_file).to receive(:open).with('/var/lib/lxc/test/rootfs/var/tomcat/manifest.yml')
      subject.write_config
    end

    it 'should render tomcat8 default config' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/default/tomcat8', '/var/lib/lxc/test/rootfs/etc/default/tomcat8', hash_including(guest: guest, model: model))
      subject.write_config
    end

    it 'should render server.xml' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/tomcat8/server.xml', '/var/lib/lxc/test/rootfs/etc/tomcat8/server.xml', 0640, guest: guest, model: model)
      subject.write_config
    end

    it 'should render servlet.xml as ROOT.xml' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/tomcat8/servlet.xml', '/var/lib/lxc/test/rootfs/etc/tomcat8/Catalina/localhost/ROOT.xml', 0640, hash_including(guest: guest, model: model))
      subject.write_config
    end

    it 'should render tomcat-users.xml' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/tomcat8/tomcat-users.xml', '/var/lib/lxc/test/rootfs/etc/tomcat8/tomcat-users.xml', 0640, guest: guest, model: model)
      subject.write_config
    end

    it 'should remove genuine root app' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', 'rm -rf /var/lib/tomcat8/webapps/ROOT', 'Failed to remove genuine root app for tomcat')
      subject.write_config
    end

    it 'should chown tomcat directories' do
      expect(subject).to receive(:chroot).with('/var/lib/lxc/test/rootfs', 'chown -R tomcat8:tomcat8 /var/tomcat /etc/tomcat8')
      subject.write_config
    end
  end

  describe 'service_name' do
    it 'should return tomcat8' do
      expect(subject.service_name).to eq 'tomcat8'
    end
  end

  describe 'interpolate_value' do
    it 'should replace %TARGET% with /var/tomcat' do
      expect(subject.interpolate_value('path/%TARGET%/file')).to eq 'path//var/tomcat/file'
    end

    it 'should replace %DATA_DIR% with /var/tomcat/data' do
      expect(subject.interpolate_value('path/%DATA_DIR%/file')).to eq 'path//var/tomcat/data/file'
    end

    it 'should replace both placeholders' do
      expect(subject.interpolate_value('%TARGET%/%DATA_DIR%')).to eq '/var/tomcat//var/tomcat/data'
    end

    it 'should convert non-string values to string' do
      expect(subject.interpolate_value(42)).to eq '42'
    end

    it 'should return unchanged string when no placeholders present' do
      expect(subject.interpolate_value('no_placeholder')).to eq 'no_placeholder'
    end
  end

  describe 'auto_restart' do
    it 'should return false' do
      expect(subject.auto_restart).to eq false
    end
  end

  describe 'auto_start' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(host).to receive(:exec)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:render_to_remote)
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Add Tomcat to runlevel default')
      subject.auto_start
    end

    it 'should link tomcat8 service to multi-user.target.wants' do
      expect(host).to receive(:exec).with("ln -sf /etc/systemd/system/tomcat8.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should create overlay directory' do
      expect(subject).to receive(:mkdir_p).with(subject.overlay_path)
      subject.auto_start
    end

    it 'should render restart drop-in' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/support/etc/systemd/unit.d/restart.conf', "#{subject.overlay_path}/restart.conf")
      subject.auto_start
    end

    it 'should render fix_perms.conf drop-in' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/tomcat8.service.d/fix_perms.conf', "#{subject.overlay_path}/fix_perms.conf")
      subject.auto_start
    end

    it 'should chown overlay path' do
      expect(host).to receive(:exec).with("chown -R 100000:100000 #{subject.overlay_path}")
      subject.auto_start
    end
  end
end