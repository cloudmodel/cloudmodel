require 'spec_helper'

describe CloudModel::Workers::Services::PhpfpmWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {double 'Phpfpm', class: CloudModel::Services::Phpfpm}
  subject {CloudModel::Workers::Services::PhpfpmWorker.new lxc, model}

  describe 'patch_php_ini' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(subject).to receive(:chroot!)
    end

    it 'should use sed to patch php.ini with given key and value' do
      allow(CloudModel).to receive_message_chain(:config, :php_version).and_return('8.2')
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', "sed -i 's/upload_max_filesize = .*/upload_max_filesize = 10M/' /etc/php/8.2/fpm/php.ini", 'Failed to config PHP option upload_max_filesize')
      subject.patch_php_ini(:upload_max_filesize, '10M')
    end
  end

  describe 'write_config' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(host).to receive(:exec)
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:render_to_remote)
      allow(subject).to receive(:chroot!)
      allow(subject).to receive(:patch_php_ini)
      allow(model).to receive(:php_upload_max_filesize).and_return(10)
      allow(CloudModel).to receive_message_chain(:config, :php_version).and_return('8.2')
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Write PHP FPM config')
      subject.write_config
    end

    it 'should render www.conf pool config' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/php/fpm/pool.d/www.conf', '/var/lib/lxc/test/rootfs/etc/php/8.2/fpm/pool.d/www.conf', 644, guest: guest, model: model)
      subject.write_config
    end

    it 'should render msmtp.ini' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/php/fpm/conf.d/30-msmtp.ini', '/var/lib/lxc/test/rootfs/etc/php/8.2/fpm/conf.d/30-msmtp.ini', 644, guest: guest, model: model)
      subject.write_config
    end

    it 'should remove old apcu.ini and render new one' do
      expect(host).to receive(:exec).with('rm /var/lib/lxc/test/rootfs/etc/php/8.2/mods-available/apcu.ini')
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/php/fpm/conf.d/20-apcu.ini', '/var/lib/lxc/test/rootfs/etc/php/8.2/mods-available/apcu.ini', 644, guest: guest, model: model)
      subject.write_config
    end

    it 'should patch upload_max_filesize' do
      expect(subject).to receive(:patch_php_ini).with(:upload_max_filesize, '10M')
      subject.write_config
    end

    it 'should patch post_max_size to upload_max_filesize + 6' do
      expect(subject).to receive(:patch_php_ini).with(:post_max_size, '16M')
      subject.write_config
    end

    it 'should create www user' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', "groupadd -f -r -g 1001 www && id -u www || useradd -c 'added by cloud_model for nginx' -d /var/www -s /bin/bash -r -g 1001 -u 1001 www", "Failed to add www user")
      subject.write_config
    end
  end

  describe 'service_name' do
    it 'should return php-fpm' do
      expect(subject.service_name).to eq 'php-fpm'
    end
  end

  describe 'auto_restart' do
    it 'should return true' do
      expect(subject.auto_restart).to eq true
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

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with("ln -sf /lib/systemd/system/php-fpm.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/")
      subject.auto_start
    end

    it 'should write restart drop-in since auto_restart is true' do
      expect(subject).to receive(:mkdir_p).with(subject.overlay_path)
      expect(subject).to receive(:render_to_remote).with("/cloud_model/support/etc/systemd/unit.d/restart.conf", "#{subject.overlay_path}/restart.conf", 644)
      subject.auto_start
    end
  end
end