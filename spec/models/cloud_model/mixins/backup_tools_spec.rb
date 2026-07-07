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
    it 'applies the retention policy to any timestamp list (e.g. ZFS snapshot names)' do
      keep = (0..2).map { |i| (Time.now - i.days).strftime '%Y%m%d%H%M%S' }
      old  = (Time.now - 8.years).strftime '%Y%m%d%H%M%S'

      expect(CloudModel::Mixins::BackupTools.disposable_timestamps(keep + [old])).to eq [old]
    end
  end

  describe 'list_disposable_backups' do
    it "should keep last 3 backups" do
      keep_backups = [
        (Time.now-1.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-2.years).strftime("%Y%m%d%H%M%S"),
        (Time.now-6.years).strftime("%Y%m%d%H%M%S"),
      ]
      disposable_backups = [
        (Time.now-8.years).strftime("%Y%m%d%H%M%S"),    
        (Time.now-13.years).strftime("%Y%m%d%H%M%S"), 
        (Time.now-15.years).strftime("%Y%m%d%H%M%S"),    
      ]
      backups = keep_backups + disposable_backups
    
      allow(subject).to receive(:list_backups).and_return backups
      expect(subject.list_disposable_backups).to match_array disposable_backups
    end
  
    it "should keep all backups of the last 3 days" do
      keep_backups = [
        (Time.now-1.days).strftime("%Y%m%d%H%M%S"),   # less than 3 days old
        (Time.now-36.hours).strftime("%Y%m%d%H%M%S"), # less than 3 days old
        (Time.now-2.days).strftime("%Y%m%d%H%M%S"),   # less than 3 days old
        (Time.now-60.hours).strftime("%Y%m%d%H%M%S"), # less than 3 days old
      ]
      disposable_backups = [
        (Time.now-3.days-5.minutes).strftime("%Y%m%d%H%M%S"), # from the last week, but less than 4 days ago
        (Time.now-8.years).strftime("%Y%m%d%H%M%S"),    
        (Time.now-13.years).strftime("%Y%m%d%H%M%S"), 
        (Time.now-15.years).strftime("%Y%m%d%H%M%S"),    
      ]
      backups = keep_backups + disposable_backups
    
      allow(subject).to receive(:list_backups).and_return backups
      expect(subject.list_disposable_backups).to match_array disposable_backups
    end
  
    it "should keep one backup for the last 7 days" do
      keep_backups = [
        (Time.now-1.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-2.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-3.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-4.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-5.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-6.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-7.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-14.days).strftime("%Y%m%d%H%M%S"),
        (Time.now-45.hours).strftime("%Y%m%d%H%M%S"),    
      ]
      disposable_backups = [
        (Time.now-8.days).strftime("%Y%m%d%H%M%S"),    
        (Time.now-13.days).strftime("%Y%m%d%H%M%S"), 
        (Time.now-15.days).strftime("%Y%m%d%H%M%S"),    
      ]
      backups = keep_backups + disposable_backups
    
      allow(subject).to receive(:list_backups).and_return backups
      expect(subject.list_disposable_backups).to match_array disposable_backups
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