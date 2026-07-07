# encoding: UTF-8

require 'spec_helper'
require 'tmpdir'

describe CloudModel::BackupCleanup do
  subject(:cleanup) { described_class.new }

  let(:root) { Dir.mktmpdir 'backup_cleanup' }

  before do
    allow(CloudModel.config).to receive(:backup_directory).and_return(root)
  end

  after do
    FileUtils.remove_entry root
  end

  def make_backup dir, timestamp, link_latest: false
    FileUtils.mkdir_p "#{dir}/#{timestamp}"
    File.write "#{dir}/#{timestamp}/dump.sql", 'data'
    if link_latest
      FileUtils.rm_f "#{dir}/latest"
      FileUtils.ln_s "#{dir}/#{timestamp}", "#{dir}/latest"
    end
  end

  # A real guest with an embedded mongodb service (validations bypassed).
  def create_guest_with_service host_id: BSON::ObjectId.new
    service_id = BSON::ObjectId.new
    CloudModel::Guest.collection.insert_one(
      'host_id' => host_id,
      'services' => [{'_id' => service_id, '_type' => 'CloudModel::Services::Mongodb'}]
    )
    CloudModel::Guest.where(id: CloudModel::Guest.collection.find('services._id' => service_id).first['_id']).first
  end

  describe 'orphaned_service_dirs' do
    it 'flags dirs whose guest or service is gone and keeps existing ones' do
      guest = create_guest_with_service
      service = guest.services.first
      make_backup service.backup_directory, '20260101000000', link_latest: true

      orphan = "#{root}/#{guest.host_id}/#{BSON::ObjectId.new}/services/#{BSON::ObjectId.new}"
      make_backup orphan, '20250101000000', link_latest: true

      expect(cleanup.orphaned_service_dirs).to eq [orphan]
    end

    it 'ignores paths that are not object ids' do
      FileUtils.mkdir_p "#{root}/not-an-id/also-not/services/nope"
      create_guest_with_service # sanity data only

      expect(cleanup.orphaned_service_dirs).to eq []
    end
  end

  describe 'orphaned_replset_dirs' do
    it 'flags dirs of deleted replica sets' do
      set = CloudModel::MongodbReplicationSet.create! name: 'rs-live'
      make_backup set.backup_directory, '20260101000000', link_latest: true

      orphan = "#{root}/mongodb_replication_sets/#{BSON::ObjectId.new}"
      make_backup orphan, '20250101000000'

      expect(cleanup.orphaned_replset_dirs).to eq [orphan]
    end
  end

  describe 'retention_disposable_dirs' do
    it 'lists over-retention backups of existing subjects' do
      set = CloudModel::MongodbReplicationSet.create! name: 'rs-live'
      old = (Time.now - 12.months).strftime '%Y%m%d%H%M%S'
      make_backup set.backup_directory, old
      3.times do |i|
        make_backup set.backup_directory, (Time.now - i.hours).strftime('%Y%m%d%H%M%S'), link_latest: i.zero?
      end

      expect(cleanup.retention_disposable_dirs).to eq ["#{set.backup_directory}/#{old}"]
    end
  end

  describe 'dangling_latest_links and empty_dirs' do
    it 'finds dangling latest links but not valid ones' do
      dir = "#{root}/mongodb_replication_sets/#{BSON::ObjectId.new}"
      make_backup dir, '20260101000000', link_latest: true
      dangling = "#{root}/mongodb_replication_sets/#{BSON::ObjectId.new}"
      FileUtils.mkdir_p dangling
      FileUtils.ln_s "#{dangling}/20200101000000", "#{dangling}/latest"

      expect(cleanup.dangling_latest_links).to eq ["#{dangling}/latest"]
    end

    it 'lists empty dirs deepest first' do
      FileUtils.mkdir_p "#{root}/a/b/c"

      expect(cleanup.empty_dirs.first).to eq "#{root}/a/b/c"
    end
  end

  describe 'sanity_check!' do
    it 'refuses to run against an empty database' do
      expect { cleanup.sanity_check! }.to raise_error(/no guests or replica sets/)
    end

    it 'refuses to run without the backup root' do
      allow(CloudModel.config).to receive(:backup_directory).and_return("#{root}/missing")
      expect { cleanup.sanity_check! }.to raise_error(/does not exist/)
    end
  end

  describe 'cleanup!' do
    let(:output) { StringIO.new }

    it 'deletes nothing on a dry run' do
      CloudModel::MongodbReplicationSet.create! name: 'rs-live'
      orphan = "#{root}/mongodb_replication_sets/#{BSON::ObjectId.new}"
      make_backup orphan, '20250101000000'

      cleanup.cleanup! dry_run: true, output: output

      expect(File.directory?(orphan)).to eq true
      expect(output.string).to match(/\[dry-run\] rm -r #{Regexp.escape orphan}/)
    end

    it 'removes orphans, dangling links and collapses empty husks' do
      set = CloudModel::MongodbReplicationSet.create! name: 'rs-live'
      make_backup set.backup_directory, '20260101000000', link_latest: true

      guest = create_guest_with_service
      orphan = "#{root}/#{guest.host_id}/#{BSON::ObjectId.new}/services/#{BSON::ObjectId.new}"
      make_backup orphan, '20250101000000', link_latest: true

      cleanup.cleanup! dry_run: false, output: output

      # the whole orphaned guest tree collapses, live backups stay
      expect(File.exist?("#{root}/#{guest.host_id}")).to eq false
      expect(File.directory?("#{set.backup_directory}/20260101000000")).to eq true
      expect(File.exist?("#{set.backup_directory}/latest")).to eq true
    end
  end
end
