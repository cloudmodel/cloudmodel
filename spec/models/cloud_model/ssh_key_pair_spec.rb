# encoding: UTF-8

require 'spec_helper'
require 'tmpdir'

describe CloudModel::SshKeyPair do
  let(:dir) { Dir.mktmpdir 'ssh_key_pair' }
  let(:key_file) { "#{dir}/keys/id_test" }
  subject { described_class.new key_file, type: 'rsa', bits: 4096 }

  after do
    FileUtils.rm_rf dir
  end

  def write_pair
    FileUtils.mkdir_p File.dirname(key_file)
    File.write key_file, 'private'
    File.write "#{key_file}.pub", "ssh-rsa AAAA\n"
  end

  describe '#present?' do
    it 'needs both halves of the pair' do
      expect(subject.present?).to eq false
      FileUtils.mkdir_p File.dirname(key_file)
      File.write key_file, 'private'
      expect(subject.present?).to eq false
      File.write "#{key_file}.pub", 'ssh-rsa AAAA'
      expect(subject.present?).to eq true
    end
  end

  describe '#ensure!' do
    it 'generates the pair (creating the directory) when missing' do
      expect(subject).to receive(:local_exec!).with(
        "ssh-keygen -q -N '' -t rsa -b 4096 -f #{key_file}", "Failed to generate SSH key pair #{key_file}"
      ) { write_pair }

      expect(subject.ensure!).to eq true
      expect(File.directory?(File.dirname(key_file))).to eq true
      expect(File.stat(key_file).mode & 0777).to eq 0600
    end

    it 'passes a comment when given' do
      pair = described_class.new key_file, comment: 'my key'
      expect(pair).to receive(:local_exec!).with("ssh-keygen -q -N '' -t ed25519 -C my\\ key -f #{key_file}", anything) { write_pair }
      pair.ensure!
    end

    it 'leaves an existing pair alone' do
      write_pair
      expect(subject).not_to receive(:local_exec!)
      expect(subject.ensure!).to eq true
    end
  end

  describe '#public_key' do
    it 'reads the stripped public key' do
      write_pair
      expect(subject.public_key).to eq 'ssh-rsa AAAA'
    end
  end
end
