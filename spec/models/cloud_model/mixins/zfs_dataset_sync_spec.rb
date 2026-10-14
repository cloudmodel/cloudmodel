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
    allow(target).to receive(:private_address).and_return('10.42.0.2')
    # default: the target has no copy of the dataset yet → full stream; no
    # moved-aside datasets to clean up
    allow(target).to receive(:exec).and_return([false, ''])
    allow(source).to receive(:exec).and_return([false, ''])
    allow(target).to receive(:exec).with(/zfs list -H -o name -t snapshot/).and_return([false, "dataset does not exist\n"])
    allow(source).to receive(:exec).with(/zfs list -H -o name -t snapshot/).and_return([true, "guests/build/type1/tmpl1@ready\n"])
  end

  describe '#zfs_send_args (full vs incremental)' do
    before do
      source.zfs_sync_key_deployed_at = Time.now
      target.zfs_sync_key_deployed_at = Time.now
    end

    it 'sends incrementally from the target´s newest snapshot when the source still has it' do
      allow(target).to receive(:exec).with('zfs list -H -o name -t snapshot -d 1 -s creation guests/build/web/img1/amd64')
        .and_return([true, "guests/build/web/img1/amd64@v1\nguests/build/web/img1/amd64@v2\n"])
      allow(source).to receive(:exec).with('zfs list -H -o name -t snapshot -d 1 -s creation guests/build/web/img1/amd64')
        .and_return([true, "guests/build/web/img1/amd64@v1\nguests/build/web/img1/amd64@v2\nguests/build/web/img1/amd64@v3\n"])

      expect(target).not_to receive(:exec!)
      expect(syncer).to receive(:local_exec!).with(/zfs list guests\/build\/web\/img1/, anything).ordered
      expect(syncer).to receive(:local_exec!).with(/'zfs send -p -i guests\/build\/web\/img1\/amd64@v2 guests\/build\/web\/img1\/amd64@v3 \| ssh .* "zfs receive -u -F guests\/build\/web\/img1\/amd64"'/, anything).ordered

      syncer.sync_zfs_dataset! source, target, 'guests/build/web/img1/amd64', snapshot: 'guests/build/web/img1/amd64@v3'
    end

    it 'moves a dataset without a common snapshot aside (clones stay valid) and sends a full stream' do
      allow(target).to receive(:exec).with(/zfs list -H -o name -t snapshot/).and_return([true, "guests/build/type1/tmpl1@pruned\n"])
      allow(Time).to receive(:now).and_return(Time.utc(2026, 10, 14, 12, 0, 0))

      expect(target).to receive(:exec!).with(
        'zfs rename guests/build/type1/tmpl1 guests/build/type1/tmpl1-stale-20261014120000 && zfs set canmount=off guests/build/type1/tmpl1-stale-20261014120000',
        /could not be moved aside/
      ).ordered
      expect(syncer).to receive(:local_exec!).with(/zfs list guests\/build\/type1 /, anything).ordered
      expect(syncer).to receive(:local_exec!).with(/'zfs send -p guests\/build\/type1\/tmpl1@ready \| ssh /, anything).ordered

      syncer.sync_zfs_dataset! source, target, 'guests/build/type1/tmpl1'
    end

    it 'treats an existing dataset without snapshots as a leftover too' do
      allow(target).to receive(:exec).with(/zfs list -H -o name -t snapshot/).and_return([true, ""])
      expect(target).to receive(:exec!).with(/^zfs rename guests\/build\/type1\/tmpl1 guests\/build\/type1\/tmpl1-stale-/, anything)

      syncer.sync_zfs_dataset! source, target, 'guests/build/type1/tmpl1'
    end

    it 'cleans up moved-aside datasets nothing depends on any more after a sync' do
      allow(target).to receive(:exec).with('zfs list -H -o name -d 1 -t filesystem guests/build/type1')
        .and_return([true, "guests/build/type1\nguests/build/type1/tmpl1\nguests/build/type1/tmpl1-stale-20260101000000\nguests/build/type1/other\n"])
      expect(target).to receive(:exec).with('zfs destroy -r guests/build/type1/tmpl1-stale-20260101000000').and_return([false, 'has dependent clones'])
      expect(target).not_to receive(:exec).with(/zfs destroy -r guests\/build\/type1\/other/)

      syncer.sync_zfs_dataset! source, target, 'guests/build/type1/tmpl1'
    end

    it 'addresses the peer by its private address, not the controller´s route to it' do
      allow(target).to receive(:ssh_address).and_return('203.0.113.7')
      # the controller's own hop may use its route (public); the peer hop stays private
      expect(syncer).to receive(:local_exec!).with(/^ssh -i \/data\/keys\/id_rsa root@203.0.113.7 'zfs list/, anything)
      expect(syncer).to receive(:local_exec!).with(/root@10.42.0.1 'zfs send .* root@10.42.0.2 "zfs receive/, anything)

      syncer.sync_zfs_dataset! source, target, 'guests/build/type1/tmpl1'
    end
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
    context 'when the sync key cannot be put on the hosts' do
      before do
        allow(syncer).to receive(:provision_zfs_sync_key!).and_return(false)
      end

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

    context 'when a host lacks the sync key' do
      let(:worker) { double CloudModel::Workers::HostWorker }

      before do
        source.zfs_sync_key_deployed_at = Time.now
        allow(CloudModel::Workers::HostWorker).to receive(:new).with(target).and_return(worker)
      end

      it 'pushes the key to that host first and then streams direct' do
        expect(worker).to receive(:deploy_zfs_sync_key) { target.zfs_sync_key_deployed_at = Time.now }
        expect(CloudModel::Workers::HostWorker).not_to receive(:new).with(source)
        expect(syncer).to receive(:local_exec!).with(/zfs list guests\/build\/type1/, anything).ordered
        expect(syncer).to receive(:local_exec!).with(/ssh -i \/root\/.ssh\/zfs_sync .* "zfs receive -u -F guests\/build\/type1\/tmpl1"/, /\(direct\)/).ordered

        expect(syncer.sync_zfs_dataset!(source, target, 'guests/build/type1/tmpl1')).to eq true
      end

      it 'falls back to the controller route when the push fails' do
        allow(worker).to receive(:deploy_zfs_sync_key).and_raise('host unreachable')
        allow(CloudModel).to receive(:log_exception)
        expect(syncer).to receive(:local_exec!).with(/^ssh -C -i \/data\/keys\/id_rsa root@10.42.0.2 'zfs list/, anything).ordered
        expect(syncer).to receive(:local_exec!).with(/^ssh -C -i .* 'zfs send -p guests\/build\/type1\/tmpl1@ready' \| ssh -C -i .* 'zfs receive -u -F guests\/build\/type1\/tmpl1'$/, anything).ordered

        expect(syncer.sync_zfs_dataset!(source, target, 'guests/build/type1/tmpl1')).to eq true
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
