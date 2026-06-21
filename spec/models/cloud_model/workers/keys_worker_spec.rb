# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Workers::KeysWorker do
  before do
    allow(CloudModel::Host).to receive(:all).and_return([])
  end

  subject { CloudModel::Workers::KeysWorker.new }

  describe '#initialize' do
    it 'should set host to a MockHost' do
      expect(subject.instance_variable_get(:@host)).to be_a CloudModel::Workers::MockHost
    end

    it 'should set hosts from Host.all' do
      hosts = [double('host1'), double('host2')]
      allow(CloudModel::Host).to receive(:all).and_return(hosts)
      worker = CloudModel::Workers::KeysWorker.new
      expect(worker.instance_variable_get(:@hosts)).to eq hosts
    end
  end

  describe '#add_new_ssh_key' do
    it 'should append public key to authorized_keys' do
      host = double 'host'
      subject.instance_variable_set :@new_public_key, 'ssh-rsa AAAA newkey'
      expect(host).to receive(:exec).with(%r{>> /root/.ssh/authorized_keys})
      subject.add_new_ssh_key(host)
    end
  end

  describe '#remove_old_ssh_key' do
    it 'should overwrite authorized_keys with new key only' do
      host = double 'host'
      subject.instance_variable_set :@new_public_key, 'ssh-rsa AAAA newkey'
      expect(host).to receive(:exec).with(%r{> /root/.ssh/authorized_keys})
      subject.remove_old_ssh_key(host)
    end
  end

  describe '#create_ssh_priv_key' do
    it 'should generate a new RSA key pair' do
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(subject).to receive(:local_exec!)
      allow(subject).to receive(:local_exec)

      expect(subject).to receive(:local_exec!).with("rm -rf /data/new_keys", "Failed remove new key dir")
      expect(subject).to receive(:local_exec!).with("mkdir -p /data/new_keys", "Failed to create new key dir")
      expect(subject).to receive(:local_exec).with("ssh-keygen -N '' -t rsa -b 4096 -f /data/new_keys/id_rsa")

      subject.create_ssh_priv_key
    end
  end

  describe '#read_ssh_pub_key' do
    it 'should read the new public key' do
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(File).to receive(:read).with('/data/new_keys/id_rsa.pub').and_return("ssh-rsa AAAA newkey \n")

      subject.read_ssh_pub_key
      expect(subject.instance_variable_get(:@new_public_key)).to eq 'ssh-rsa AAAA newkey'
    end
  end

  describe '#update_ssh_priv_key' do
    it 'should rename new_keys to keys' do
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(File).to receive(:exist?).with('/data/keys').and_return(false)
      expect(File).to receive(:rename).with('/data/new_keys', '/data/keys')

      subject.update_ssh_priv_key
    end

    it 'should backup existing keys directory' do
      allow(CloudModel.config).to receive(:data_directory).and_return('/data')
      allow(File).to receive(:exist?).with('/data/keys').and_return(true)
      expect(File).to receive(:rename).with('/data/keys', /\/data\/keys_/)
      expect(File).to receive(:rename).with('/data/new_keys', '/data/keys')

      subject.update_ssh_priv_key
    end
  end

  describe '#config_sshd' do
    it 'should render sshd_config and reload sshd' do
      target_host = double 'target_host'
      allow(subject).to receive(:render_to_remote)
      expect(target_host).to receive(:exec!).with("systemctl reload sshd", "Failed to reload SSHd")

      subject.config_sshd(target_host)
    end
  end

  describe '#renew' do
    it 'should run deploy steps' do
      allow(subject).to receive(:run_steps)
      allow(subject).to receive(:distance_of_time_in_words_to_now).and_return('5 minutes')

      expect(subject).to receive(:run_steps).with(:deploy, anything, anything)
      expect { subject.renew }.to output(/Finished/).to_stdout
    end
  end
end
