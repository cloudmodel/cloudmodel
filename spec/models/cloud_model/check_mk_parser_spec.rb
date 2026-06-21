# encoding: UTF-8

require 'spec_helper'

describe CloudModel::CheckMkParser do
  describe '.parse' do
    it 'should parse check_mk section' do
      result = CloudModel::CheckMkParser.parse "<<<check_mk>>>\nVersion: 2.2.0\nAgentOS: linux\n"
      expect(result['check_mk']['version']).to eq '2.2.0'
      expect(result['check_mk']['agent_os']).to eq 'linux'
    end

    it 'should parse mem section' do
      result = CloudModel::CheckMkParser.parse "<<<mem>>>\nMemTotal: 8192 kB\nMemFree: 4096 kB\n"
      expect(result['mem']['mem_total']).to eq '8192 kB'
      expect(result['mem']['mem_free']).to eq '4096 kB'
    end

    it 'should parse df section' do
      result = CloudModel::CheckMkParser.parse "<<<df>>>\n/dev/sda1 ext4 100000 50000 45000 53% /\n"
      expect(result['df']['/dev/sda1']['mountpoint']).to eq '/'
      expect(result['df']['/dev/sda1']['used']).to eq '50000'
    end

    it 'should rename df_v2 to df' do
      result = CloudModel::CheckMkParser.parse "<<<df_v2>>>\n/dev/sda1 ext4 100000 50000 45000 53% /\n"
      expect(result['df']).not_to be_nil
      expect(result['df_v2']).to be_nil
    end

    it 'should parse cpu section' do
      result = CloudModel::CheckMkParser.parse "<<<cpu>>>\n0.5 1.0 1.5 1/200 12345 4\n"
      expect(result['cpu']['cpus']).to eq '4'
      expect(result['cpu']['last_minute_load']).to eq '0.5'
    end

    it 'should parse mounts section' do
      result = CloudModel::CheckMkParser.parse "<<<mounts>>>\n/dev/sda1 / ext4 rw,relatime 0 0\n"
      expect(result['mounts']['/dev/sda1']['mountpoint']).to eq '/'
      expect(result['mounts']['/dev/sda1']['format']).to eq 'ext4'
    end

    it 'should parse zpools section' do
      result = CloudModel::CheckMkParser.parse "<<<zpools>>>\ntank\t10G\t5G\t5G\t-\t10%\t50%\t1.00x\tONLINE\t-\n"
      expect(result['zpools']['tank'][:health]).to eq 'ONLINE'
      expect(result['zpools']['tank'][:cap_percentage]).to eq '50%'
    end

    it 'should parse multiple sections' do
      input = "<<<check_mk>>>\nVersion: 2.2.0\n<<<mem>>>\nMemTotal: 8192 kB\n"
      result = CloudModel::CheckMkParser.parse input
      expect(result['check_mk']).not_to be_nil
      expect(result['mem']).not_to be_nil
    end

    it 'should store unknown sections as data' do
      result = CloudModel::CheckMkParser.parse "<<<cgroup_cpu>>>\nsome raw data\n"
      expect(result['cgroup_cpu']['data']).to eq "some raw data\n"
    end
  end

  describe '.parse_cgroup_cpu' do
    it 'should return nil when no data key' do
      expect(CloudModel::CheckMkParser.parse_cgroup_cpu({}, 4)).to eq nil
    end

    it 'should set cpus' do
      data = "1000000000 100 200\n0 50 100\n"
      result = {'data' => data}
      CloudModel::CheckMkParser.parse_cgroup_cpu result, 2
      expect(result['cpus']).to eq 2
    end
  end
end