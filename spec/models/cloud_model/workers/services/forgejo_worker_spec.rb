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
      allow(model).to receive(:actions_runners).and_return([])
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

  describe 'write_config with an OIDC login source' do
    let(:cli) { 'GITEA_WORK_DIR=/var/lib/forgejo forgejo --config /etc/forgejo/app.ini' }

    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:chroot!).and_return('x')
      allow(subject).to receive(:chroot).and_return([true, ''])
      allow(subject).to receive(:render_to_guest)
      allow(model).to receive(:save)
      allow(model).to receive(:actions_runners).and_return([])
      model.oidc_name = 'sso'
      model.oidc_auto_discovery_url = 'https://auth.example.com/.well-known/openid-configuration'
      model.oidc_client_id = 'client'
      model.oidc_client_secret = 'secret'
      model.oidc_admin_group = 'admins'
      model.oidc_restricted_group = 'external'
      model.oidc_group_team_map = '{"staff": {"org": ["staff"]}}'
      model.oidc_skip_local_2fa = true
    end

    it 'should migrate the database first' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', "su -s /bin/bash forgejo -c #{"#{cli} migrate".shellescape}", 'Failed to migrate forgejo db').ordered
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', /admin\\ auth\\ add-oauth/, 'Failed to configure OIDC login source').ordered
      subject.write_config
    end

    it 'should add the source with the group mapping and scopes' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', /admin\\ auth\\ add-oauth/, 'Failed to configure OIDC login source') do |_, command, _|
        inner = Shellwords.split(command).last
        expect(inner).to include '--provider openidConnect'
        expect(inner).to include '--skip-local-2fa=true'
        expect(inner).to include '--group-claim-name groups'
        expect(inner).to include '--admin-group admins'
        expect(inner).to include '--restricted-group external'
        expect(Shellwords.split(inner)).to include('--group-team-map', '{"staff": {"org": ["staff"]}}')
        expect(inner).to include '--group-team-map-removal=false'
        expect(inner).to include '--scopes openid --scopes profile --scopes email --scopes groups'
      end
      subject.write_config
    end

    it 'should update an existing source of the same name instead of adding a duplicate' do
      allow(subject).to receive(:chroot).and_return([true, "1\tsso\tOAuth2\ttrue\n"])
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', /admin\\ auth\\ update-oauth\\ --id\\ 1\\ --name\\ sso/, 'Failed to configure OIDC login source')
      subject.write_config
    end
  end

  describe 'write_config with Actions runners' do
    let(:runner) { CloudModel::Services::ForgejoRunner.new runner_name: 'ci', registration_secret: 'b' * 40 }

    before do
      allow(guest).to receive(:deploy_path).and_return('/var/lib/lxc/test/rootfs')
      allow(subject).to receive(:comment_sub_step)
      allow(subject).to receive(:chroot!).and_return('x')
      allow(subject).to receive(:render_to_guest)
      allow(model).to receive(:save)
      allow(model).to receive(:actions_runners).and_return([runner])
    end

    it 'should register each runner offline with its shared secret' do
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', /migrate/, 'Failed to migrate forgejo db').ordered
      expect(subject).to receive(:chroot!).with('/var/lib/lxc/test/rootfs', /forgejo-cli\\ actions\\ register\\ --name\\ ci\\ --labels\\ ubuntu-latest,self-hosted\\ --secret\\ b{40}/, 'Failed to register runner ci').ordered
      subject.write_config
    end

    it 'should skip a runner that has no secret yet' do
      runner.registration_secret = nil
      expect(subject).not_to receive(:chroot!).with(anything, /actions\\ register/, anything)
      subject.write_config
    end

    it 'should not register runners when Actions are disabled' do
      model.actions_enabled = false
      expect(subject).not_to receive(:chroot!).with(anything, /actions\\ register/, anything)
      subject.write_config
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
