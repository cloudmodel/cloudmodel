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