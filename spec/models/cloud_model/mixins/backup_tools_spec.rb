# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Mixins::BackupTools do
  class TestBackupToolsModel
    include Mongoid::Document
    include CloudModel::Mixins::BackupTools
    
    def backup_directory
      '/var/backups/my_item'
    end
  end
  
  subject { TestBackupToolsModel.new }
  
  describe 'list_backups' do
    it 'should return all items in backup_directory matching a compressed timestamp' do
      expect(Dir).to receive(:entries).with('/var/backups/my_item').and_return [
        '.',
        '..',
        '_deleted',
        '20200403133742',
        '20161224204217',
        '20060714162319.in_progress',
      ]
      
      expect(subject.list_backups).to eq ['20200403133742', '20161224204217']
    end
    
    it 'should return empty array if backup directory does not exist' do
      allow(Dir).to receive(:entries).and_raise Errno::ENOENT
      
      expect(subject.list_backups).to eq []
    end
  end
  
  describe 'last_backup_at' do
    it 'should return the time of the backup the latest symlink points to' do
      expect(File).to receive(:symlink?).with('/var/backups/my_item/latest').and_return true
      expect(File).to receive(:exist?).with('/var/backups/my_item/latest').and_return true
      expect(File).to receive(:readlink).with('/var/backups/my_item/latest').and_return '/var/backups/my_item/20200403133742'

      expect(subject.last_backup_at).to eq Time.strptime('20200403133742', '%Y%m%d%H%M%S')
    end

    it 'should return nil when there is no latest symlink' do
      allow(File).to receive(:symlink?).and_return false

      expect(subject.last_backup_at).to be_nil
    end

    it 'should return nil for a dangling latest symlink (target removed = fail)' do
      allow(File).to receive(:symlink?).and_return true
      allow(File).to receive(:exist?).and_return false

      expect(subject.last_backup_at).to be_nil
    end

    it 'should not be fooled by a newer incomplete backup the symlink does not point to' do
      # A crashed run can leave a newer timestamp dir behind; latest still
      # points at the last good one.
      allow(File).to receive(:symlink?).and_return true
      allow(File).to receive(:exist?).and_return true
      allow(File).to receive(:readlink).and_return '/var/backups/my_item/20161224204217'

      expect(subject.last_backup_at).to eq Time.strptime('20161224204217', '%Y%m%d%H%M%S')
    end

    it 'should return nil when the latest link target is not a valid timestamp' do
      allow(File).to receive(:symlink?).and_return true
      allow(File).to receive(:exist?).and_return true
      allow(File).to receive(:readlink).and_return '/var/backups/my_item/broken'

      expect(subject.last_backup_at).to be_nil
    end
  end

  describe 'delete_backup' do
    require 'tmpdir'

    let(:root) { Dir.mktmpdir 'delete_backup' }
    let(:model) do
      model = TestBackupToolsModel.new
      allow(model).to receive(:backup_directory).and_return "#{root}/subject"
      model
    end

    after { FileUtils.remove_entry root }

    def make_backup timestamp, link_latest: false
      FileUtils.mkdir_p "#{root}/subject/#{timestamp}"
      File.write "#{root}/subject/#{timestamp}/dump", 'data'
      FileUtils.ln_sf timestamp, "#{root}/subject/latest" if link_latest
    end

    it 'deletes a version and re-points latest to the newest remaining one' do
      make_backup '20240101000000'
      make_backup '20240102000000', link_latest: true

      expect(model.delete_backup('20240102000000')).to eq true
      expect(File.directory?("#{root}/subject/20240102000000")).to eq false
      expect(File.readlink("#{root}/subject/latest")).to eq '20240101000000'
    end

    it 'keeps latest untouched when deleting an older version' do
      make_backup '20240101000000'
      make_backup '20240102000000', link_latest: true

      expect(model.delete_backup('20240101000000')).to eq true
      expect(File.readlink("#{root}/subject/latest")).to eq '20240102000000'
    end

    it 'removes the whole directory when the last backup goes' do
      make_backup '20240101000000', link_latest: true

      expect(model.delete_backup('20240101000000')).to eq true
      expect(File.exist?("#{root}/subject")).to eq false
    end

    it 'is false for versions that do not exist' do
      FileUtils.mkdir_p "#{root}/subject"
      expect(model.delete_backup('20240101000000')).to eq false
    end

    it 'rejects invalid timestamps' do
      expect { model.delete_backup('../../etc') }.to raise_error ArgumentError
    end
  end

  describe 'backups_with_info' do
    it 'returns timestamps with size and latest flag, newest first' do
      allow(subject).to receive(:list_backups).and_return %w(20240102000000 20240101000000)
      allow(File).to receive(:readlink).with('/var/backups/my_item/latest').and_return '20240102000000'
      allow(subject).to receive(:`).with(/\Adu -sk /).and_return(
        "12\t/var/backups/my_item/20240102000000\n8\t/var/backups/my_item/20240101000000\n"
      )

      info = subject.backups_with_info
      expect(info.map { |i| i[:timestamp] }).to eq %w(20240102000000 20240101000000)
      expect(info.first).to include latest: true, size_bytes: 12 * 1024
      expect(info.last).to include latest: false, size_bytes: 8 * 1024
      expect(info.first[:time]).to eq Time.strptime('20240102000000', '%Y%m%d%H%M%S')
    end

    it 'marks nothing latest without a readable symlink' do
      allow(subject).to receive(:list_backups).and_return %w(20240101000000)
      allow(subject).to receive(:`).and_return ''

      expect(subject.backups_with_info.first[:latest]).to eq false
    end
  end

  describe '.disposable_timestamps' do
    let(:now) { Time.new(2026, 10, 27, 1, 0, 0) }
    def stamp t; t.strftime('%Y%m%d%H%M%S'); end
    def dispose backups, **opts
      CloudModel::Mixins::BackupTools.disposable_timestamps(backups, now: now, **opts)
    end

    it 'applies the retention policy to any timestamp list (e.g. ZFS snapshot names)' do
      keep = (0..2).map { |i| stamp(now - i.days) }
      old  = stamp(now - 8.years)
      expect(dispose(keep + [old])).to eq [old]
    end

    it 'always keeps the newest backups, however old' do
      backups = [now - 1.day, now - 2.years, now - 6.years, now - 8.years, now - 13.years].map { |t| stamp t }
      expect(dispose(backups)).to match_array [stamp(now - 8.years), stamp(now - 13.years)]
    end

    it 'keeps the newest backup of each recent calendar day' do
      morning = stamp(now.change(hour: 0, min: 5))
      earlier = stamp(now.change(hour: 0, min: 1))
      yesterday = (0..3).map { |h| stamp((now - 1.day).change(hour: h)) }
      backups = [morning, earlier] + yesterday
      expect(dispose(backups, retention: {recent: 0, days: 2, weeks: 0, months: 0})).to match_array [earlier] + yesterday.first(3)
    end

    it 'keeps the newest backup of each calendar week and month beyond the daily tier' do
      backups = (0...120).map { |d| stamp((now - d.days).change(hour: 0, min: 5)) }
      kept = backups - dispose(backups, retention: {recent: 0, days: 7, weeks: 6, months: 12})
      kept_dates = kept.map { |b| Date.strptime(b[0, 8], '%Y%m%d') }
      # every one of the last 7 days
      expect(kept_dates).to include(*(0...7).map { |d| now.to_date - d })
      # one per calendar week for the last 6 weeks: the week's newest day
      expect(kept_dates).to include(now.to_date.beginning_of_week - 1, now.to_date.beginning_of_week - 8)
      # one per calendar month, its last day
      expect(kept_dates).to include(Date.new(2026, 9, 30), Date.new(2026, 8, 31), Date.new(2026, 7, 31))
    end

    it 'holds the configured depth over a year of daily backups (no backup expires before a tier claims it)' do
      retention = {recent: 3, days: 7, weeks: 6, months: 12}
      start = Time.new(2025, 9, 1, 0, 5, 0)
      present = []
      400.times do |d|
        today = start + d.days
        present << stamp(today)
        present -= CloudModel::Mixins::BackupTools.disposable_timestamps(present, retention: retention, now: today + 30.minutes)
      end
      last = start + 399.days
      dates = present.map { |b| Date.strptime(b[0, 8], '%Y%m%d') }.sort

      expect(dates.count { |d| d > last.to_date - 7 }).to eq 7
      expect(dates.first).to be <= (last.to_date << 11).beginning_of_month + 31
      expect(dates.size).to be_between(20, 26)
    end

    it 'uses the configured retention by default' do
      allow(CloudModel.config).to receive(:backup_retention).and_return(recent: 1, days: 0, weeks: 0, months: 0)
      backups = [stamp(now), stamp(now - 1.day)]
      expect(dispose(backups)).to eq [stamp(now - 1.day)]
    end

    it 'ignores names that are not timestamps for the calendar tiers' do
      expect(dispose(['20261027010000', 'latest'], retention: {recent: 0, days: 1, weeks: 0, months: 0})).to eq ['latest']
    end
  end

  describe 'list_disposable_backups' do
    it 'applies the retention policy to the backup directory' do
      allow(subject).to receive(:list_backups).and_return ['20261027010000', '20101027010000']
      expect(CloudModel::Mixins::BackupTools).to receive(:disposable_timestamps).with(['20261027010000', '20101027010000']).and_return ['20101027010000']
      expect(subject.list_disposable_backups).to eq ['20101027010000']
    end
  end

  describe 'cleanup_backups' do
    it 'should delete disposable backups' do
      expect(subject).to receive(:list_disposable_backups).and_return ['20200403133742', '20161224204217']
      
      expect(FileUtils).to receive(:rm_rf).with('/var/backups/my_item/20200403133742')
      expect(FileUtils).to receive(:rm_rf).with('/var/backups/my_item/20161224204217')
      
      expect(subject.cleanup_backups).to eq true
    end
  end
end