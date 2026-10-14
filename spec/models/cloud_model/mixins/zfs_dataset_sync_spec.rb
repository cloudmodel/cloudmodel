# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Mixins::ZfsDatasetSync do
  let(:syncer) { Class.new { include CloudModel::Mixins::ZfsDatasetSync }.new }
  let(:source) { Factory.build :host, name: 'buildhost' }
  let(:target) { Factory.build :host, name: 'deployhost' }

  before do
    allow(source).to receive(:ssh_address).and_return('10.42.0.1')
    allow(target).to receive(:ssh_address).and_return('10.42.0.2')
    allow(CloudModel.config).to receive(:ssh_key_file).and_return('/data/keys/id_rsa')
    allow(syncer).to receive(:local_exec!)
  end

  describe '#direct_zfs_sync?' do
    it 'needs the sync key on both hosts' do
      expect(syncer.direct_zfs_sync?(source, target)).to eq false
      source.zfs_sync_key_deployed_at = Time.now
      expect(syncer.direct_zfs_sync?(source, target)).to eq false
      target.zfs_sync_key_deployed_at = Time.now
      expect(syncer.direct_zfs_sync?(source, target)).to eq true
    end
  end

  describe '#sync_zfs_dataset!' do
    context 'without the sync key on both hosts' do
      it 'pipes the stream through the controller' do
        expect(syncer).to receive(:local_exec!).with(
          "ssh -C -i /data/keys/id_rsa root@10.42.0.2 'zfs list guests/build/type1 >/dev/null 2>&1 || zfs create -p guests/build/type1'",
          'Failed to create parent dataset on deployhost'
        ).ordered
        expect(syncer).to receive(:local_exec!).with(
          "ssh -C -i /data/keys/id_rsa root@10.42.0.1 'zfs send -p guests/build/type1/tmpl1@ready' | ssh -C -i /data/keys/id_rsa root@10.42.0.2 'zfs receive -u -F guests/build/type1/tmpl1'",
          'Failed to sync build volume guests/build/type1/tmpl1 from buildhost to deployhost'
        ).ordered

        expect(syncer.sync_zfs_dataset!(source, target, 'guests/build/type1/tmpl1')).to eq true
      end
    end

    context 'with the sync key on both hosts' do
      before do
        source.zfs_sync_key_deployed_at = Time.now
        target.zfs_sync_key_deployed_at = Time.now
      end

      it 'streams host to host under the restricted key, parent prepared by the controller' do
        expect(syncer).to receive(:local_exec!).with(
          "ssh -i /data/keys/id_rsa root@10.42.0.2 'zfs list guests/build/type1 >/dev/null 2>&1 || zfs create -p guests/build/type1'",
          'Failed to create parent dataset on deployhost'
        ).ordered
        expect(syncer).to receive(:local_exec!).with(
          "ssh -i /data/keys/id_rsa root@10.42.0.1 'zfs send -p guests/build/type1/tmpl1@ready | " \
          "ssh -i /root/.ssh/zfs_sync -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@10.42.0.2 \"zfs receive -u -F guests/build/type1/tmpl1\"'",
          'Failed to sync build volume guests/build/type1/tmpl1 from buildhost to deployhost (direct)'
        ).ordered

        expect(syncer.sync_zfs_dataset!(source, target, 'guests/build/type1/tmpl1')).to eq true
      end

      it 'sends the given snapshot (versioned web image artifacts)' do
        expect(syncer).to receive(:local_exec!).with(/zfs list guests\/build\/web\/img1/, anything).ordered
        expect(syncer).to receive(:local_exec!).with(/zfs send -p guests\/build\/web\/img1\/amd64@v20260101000000 \| ssh -i \/root\/.ssh\/zfs_sync .* "zfs receive -u -F guests\/build\/web\/img1\/amd64"/, anything).ordered

        syncer.sync_zfs_dataset! source, target, 'guests/build/web/img1/amd64', snapshot: 'guests/build/web/img1/amd64@v20260101000000'
      end
    end

    it 'refuses names that could escape the remote command' do
      expect(syncer).not_to receive(:local_exec!)
      expect {
        syncer.sync_zfs_dataset! source, target, "guests/build/x'; rm -rf /; echo '"
      }.to raise_error(/unexpected name/)
      expect {
        syncer.sync_zfs_dataset! source, target, 'guests/build/type1/tmpl1', snapshot: 'guests/build/type1/tmpl1@ready $(id)'
      }.to raise_error(/unexpected name/)
    end
  end
end
