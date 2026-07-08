require 'spec_helper'

describe CloudModel::Workers::Services::NginxWorker do
  let(:host) { double 'host' }
  let(:guest) { double 'guest', host: host, name: 'app01' }
  let(:lxc) { double 'lxc', guest: guest, name: 'app01-c1' }
  let(:model) { CloudModel::Services::Nginx.new passenger_supported: true }

  subject { described_class.new lxc, model }

  # Deterministic plan: two files with fixed rendered contents.
  let(:conf_a) { "conf a\n" }
  let(:conf_b) { "conf b\n" }
  let(:hash_a) { Digest::SHA256.hexdigest conf_a }
  let(:hash_b) { Digest::SHA256.hexdigest conf_b }
  let(:plan) do
    [
      {template: 't/a', path: '/etc/nginx/a.conf', content: conf_a, hash: hash_a},
      {template: 't/b', path: '/etc/nginx/b.conf', content: conf_b, hash: hash_b}
    ]
  end

  before do
    allow(subject).to receive(:config_sync_plan).and_return plan
    allow(subject).to receive(:write_config_manifest)
    allow(subject).to receive(:upload_to_guest)
    allow(subject).to receive(:guest_sh).and_return [true, '']
  end

  def stub_manifest manifest
    allow(subject).to receive(:read_config_manifest).and_return manifest
  end

  def stub_remote_hashes hashes
    allow(subject).to receive(:remote_file_hash) { |path| hashes[path] }
  end

  describe 'sync_config' do
    it 'does nothing but refresh the manifest when everything is unchanged' do
      stub_manifest '/etc/nginx/a.conf' => hash_a, '/etc/nginx/b.conf' => hash_b
      stub_remote_hashes '/etc/nginx/a.conf' => hash_a, '/etc/nginx/b.conf' => hash_b

      expect(subject).not_to receive(:upload_to_guest)
      result = subject.sync_config
      expect(result[:state]).to eq :unchanged
    end

    it 'applies changed files, validates and reloads nginx' do
      stub_manifest '/etc/nginx/a.conf' => 'old-a', '/etc/nginx/b.conf' => hash_b
      stub_remote_hashes '/etc/nginx/a.conf' => 'old-a', '/etc/nginx/b.conf' => hash_b

      expect(subject).to receive(:upload_to_guest).with(conf_a, '/etc/nginx/a.conf')
      expect(subject).to receive(:guest_sh).with('nginx -t 2>&1').and_return [true, '']
      expect(subject).to receive(:guest_sh).with('systemctl reload nginx 2>&1').and_return [true, '']
      expect(subject).to receive(:write_config_manifest).with(plan)

      result = subject.sync_config
      expect(result[:state]).to eq :applied
      expect(result[:applied]).to eq ['/etc/nginx/a.conf']
    end

    it 'writes files missing on the guest without force' do
      stub_manifest({})
      stub_remote_hashes '/etc/nginx/a.conf' => nil, '/etc/nginx/b.conf' => nil

      expect(subject).to receive(:upload_to_guest).twice
      expect(subject.sync_config[:state]).to eq :applied
    end

    it 'blocks manually edited files unless forced' do
      stub_manifest '/etc/nginx/a.conf' => hash_a, '/etc/nginx/b.conf' => 'written-b'
      stub_remote_hashes '/etc/nginx/a.conf' => hash_a, '/etc/nginx/b.conf' => 'edited-b'

      expect(subject).not_to receive(:upload_to_guest)
      result = subject.sync_config
      expect(result[:state]).to eq :blocked
      expect(result[:blocked]).to eq [{path: '/etc/nginx/b.conf', reason: :edited}]
    end

    it 'blocks files with no manifest record unless forced' do
      stub_manifest({})
      stub_remote_hashes '/etc/nginx/a.conf' => 'something', '/etc/nginx/b.conf' => hash_b

      result = subject.sync_config
      expect(result[:state]).to eq :blocked
      expect(result[:blocked]).to eq [{path: '/etc/nginx/a.conf', reason: :unrecorded}]
    end

    it 'overwrites blocked files with force' do
      stub_manifest({})
      stub_remote_hashes '/etc/nginx/a.conf' => 'something', '/etc/nginx/b.conf' => hash_b

      expect(subject).to receive(:upload_to_guest).with(conf_a, '/etc/nginx/a.conf')
      expect(subject.sync_config(force: true)[:state]).to eq :applied
    end

    it 'restores the previous files when nginx -t fails' do
      stub_manifest '/etc/nginx/a.conf' => 'old-a', '/etc/nginx/b.conf' => hash_b
      stub_remote_hashes '/etc/nginx/a.conf' => 'old-a', '/etc/nginx/b.conf' => hash_b

      expect(subject).to receive(:guest_sh).with('nginx -t 2>&1').and_return [false, 'nginx: broken']
      expect(subject).to receive(:guest_sh).with(%r{mv /var/lib/cloud_model/nginx_bak/etc/nginx/a\.conf}).and_return [true, '']
      expect(subject).not_to receive(:guest_sh).with('systemctl reload nginx 2>&1')
      expect(subject).not_to receive(:write_config_manifest)

      result = subject.sync_config
      expect(result[:state]).to eq :failed
      expect(result[:output]).to eq 'nginx: broken'
    end
  end
end
