# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::Services::ForgejoWorker do
  let(:host) {double CloudModel::Host}
  let(:guest) {double CloudModel::Guest, host: host}
  let(:lxc) {double CloudModel::LxdContainer, guest: guest}
  let(:model) {CloudModel::Services::Forgejo.new}
  subject {CloudModel::Workers::Services::ForgejoWorker.new lxc, model}

  describe 'write_config' do
    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:chroot!).and_return('generated-secret')
      allow(subject).to receive(:render_to_guest)
      allow(subject).to receive(:mkdir_p)
      allow(subject).to receive(:upload_to_guest)
      allow(model).to receive(:save)
    end

    it 'should comment the sub step' do
      expect(subject).to receive(:comment_sub_step).with('Config forgejo')
      subject.write_config
    end

    it 'should generate the SECRET_KEY when missing' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', 'forgejo generate secret SECRET_KEY', 'Failed to generate SECRET_KEY').and_return('the-secret-key')
      subject.write_config
      expect(model.secret_key).to eq 'the-secret-key'
    end

    it 'should generate the INTERNAL_TOKEN when missing' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', 'forgejo generate secret INTERNAL_TOKEN', 'Failed to generate INTERNAL_TOKEN').and_return('the-internal-token')
      subject.write_config
      expect(model.internal_token).to eq 'the-internal-token'
    end

    it 'should generate the LFS_JWT_SECRET when missing' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', 'forgejo generate secret LFS_JWT_SECRET', 'Failed to generate LFS_JWT_SECRET').and_return('the-lfs-secret')
      subject.write_config
      expect(model.lfs_jwt_secret).to eq 'the-lfs-secret'
    end

    it 'should generate the oauth JWT_SECRET when missing' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', 'forgejo generate secret JWT_SECRET', 'Failed to generate JWT_SECRET').and_return('the-oauth-secret')
      subject.write_config
      expect(model.oauth_jwt_secret).to eq 'the-oauth-secret'
    end

    it 'should not regenerate secrets that are already set' do
      model.secret_key = 'existing'
      expect(subject).not_to receive(:chroot!).with(anything, 'forgejo generate secret SECRET_KEY', anything)
      subject.write_config
      expect(model.secret_key).to eq 'existing'
    end

    it 'should save the model' do
      expect(model).to receive(:save)
      subject.write_config
    end

    it 'should render app.ini' do
      expect(subject).to receive(:render_to_guest).with('/cloud_model/guest/etc/forgejo/app.ini', '/etc/forgejo/app.ini', 0600, guest: guest, model: model)
      subject.write_config
    end

    context 'without a custom logo' do
      it 'should not create the assets directory or upload a logo' do
        expect(subject).not_to receive(:mkdir_p)
        expect(subject).not_to receive(:upload_to_guest)
        subject.write_config
      end
    end

    context 'with a custom logo' do
      before { model.logo_svg = '<svg></svg>' }

      it 'should create the assets directory' do
        expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/var/lib/forgejo/custom/public/assets/img/')
        subject.write_config
      end

      it 'should upload the logo svg' do
        expect(subject).to receive(:upload_to_guest).with('<svg></svg>', '/var/lib/forgejo/custom/public/assets/img/logo.svg')
        subject.write_config
      end

      it 'should upload the favicon svg' do
        expect(subject).to receive(:upload_to_guest).with('<svg></svg>', '/var/lib/forgejo/custom/public/assets/img/favicon.svg')
        subject.write_config
      end
    end
  end

  describe 'service_name' do
    it 'should return forgejo' do
      expect(subject.service_name).to eq 'forgejo'
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

    it 'should create the systemd drop-in overlay directory' do
      expect(subject).to receive(:mkdir_p).with('/var/lib/lxc/test/rootfs/etc/systemd/system/forgejo.service.d')
      subject.auto_start
    end

    it 'should render the fix_perms drop-in' do
      expect(subject).to receive(:render_to_remote).with('/cloud_model/guest/etc/systemd/system/forgejo.service.d/fix_perms.conf', '/var/lib/lxc/test/rootfs/etc/systemd/system/forgejo.service.d/fix_perms.conf')
      subject.auto_start
    end

    it 'should call super to add service to runlevel default' do
      expect(host).to receive(:exec).with('ln -sf /lib/systemd/system/forgejo.service /var/lib/lxc/test/rootfs/etc/systemd/system/multi-user.target.wants/')
      subject.auto_start
    end
  end
end
