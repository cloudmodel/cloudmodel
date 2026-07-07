require 'spec_helper'

describe CloudModel do
  describe '#config' do
    it 'should return a CloudModel::Config instance' do
      expect(CloudModel.config).to be_a CloudModel::Config
    end

    it 'should memoize the config instance' do
      expect(CloudModel.config).to be CloudModel.config
    end
  end

  describe '#configure' do
    it 'should yield config to the block' do
      CloudModel.configure do |config|
        expect(config).to be_a CloudModel::Config
      end
    end

    it 'should allow setting config values' do
      CloudModel.configure do |config|
        config.admin_email = 'test@example.com'
      end
      expect(CloudModel.config.admin_email).to eq 'test@example.com'
    end
  end
  
  describe '#log_exception' do
  end

  describe '.backup_log' do
    it 'prefixes output with the current thread backup label' do
      expect {
        CloudModel.with_backup_label('my db') { CloudModel.backup_log 'dump started' }
      }.to output("[my db] dump started\n").to_stdout
    end

    it 'prints unprefixed without a label' do
      expect { CloudModel.backup_log 'hello' }.to output("hello\n").to_stdout
    end

    it 'restores the previous label after the block' do
      CloudModel.with_backup_label('outer') do
        CloudModel.with_backup_label('inner') {}
        expect { CloudModel.backup_log 'back' }.to output("[outer] back\n").to_stdout
      end
    end
  end

  describe '.backup_exec' do
    it 'streams stdout and stderr through backup_log and returns success' do
      expect {
        CloudModel.with_backup_label('rs0') do
          expect(CloudModel.backup_exec('echo out; echo err >&2')).to eq true
        end
      }.to output(/^\[rs0\] out$/).to_stdout
    end

    it 'returns false when the command fails' do
      expect(CloudModel.backup_exec('exit 1')).to eq false
    end
  end

  describe '.parallel_each' do
    it 'runs the block for every item' do
      seen = Queue.new
      CloudModel.parallel_each([1, 2, 3, 4, 5], concurrency: 3) { |i| seen << i }
      expect(seen.size).to eq 5
      result = []
      result << seen.pop until seen.empty?
      expect(result.sort).to eq [1, 2, 3, 4, 5]
    end

    it 'runs sequentially for concurrency <= 1' do
      order = []
      CloudModel.parallel_each([1, 2, 3], concurrency: 1) { |i| order << i }
      expect(order).to eq [1, 2, 3]
    end

    it 'actually overlaps work when concurrency > 1' do
      threads = Queue.new
      CloudModel.parallel_each([1, 2, 3], concurrency: 3) { threads << Thread.current.object_id; sleep 0.05 }
      ids = []
      ids << threads.pop until threads.empty?
      expect(ids.uniq.size).to be > 1
    end
  end
end 

