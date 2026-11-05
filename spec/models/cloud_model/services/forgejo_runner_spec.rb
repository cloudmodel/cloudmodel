# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Services::ForgejoRunner do
  it { expect(subject).to be_a CloudModel::Services::Base }

  it { expect(subject).to have_field(:forgejo_service_id).of_type(String) }
  it { expect(subject).to have_field(:instance_url).of_type(String) }
  it { expect(subject).to have_field(:runner_name).of_type(String) }
  it { expect(subject).to have_field(:registration_secret).of_type(String) }
  it { expect(subject).to have_field(:labels).of_type(Array).with_default_value_of [] }
  it { expect(subject).to have_field(:capacity).of_type(Integer).with_default_value_of 1 }
  it { expect(subject).to have_field(:scope).of_type(String) }
  it { expect(subject).to have_field(:log_level).of_type(String).with_default_value_of 'info' }
  it { expect(subject).to have_field(:runner_version).of_type(String) }

  it { expect(subject).to validate_inclusion_of(:log_level).to_allow('info', 'debug') }

  describe 'kind' do
    it { expect(subject.kind).to eq :forgejo_runner }
  end

  describe 'used_ports' do
    it 'should reserve nothing (outbound connections only)' do
      expect(subject.used_ports).to eq []
    end
  end

  describe 'components_needed' do
    it 'should require the versioned runner component' do
      expect(subject.components_needed).to eq [:"forgejo_runner@13.2.1"]
    end

    it 'should add the tool chain components of the service' do
      subject.additional_components = ['ruby@3.4.8', 'nodejs', 'rust']
      expect(subject.components_needed).to eq [:"forgejo_runner@13.2.1", :"ruby@3.4.8", :nodejs, :rust]
    end
  end

  describe 'validation' do
    it 'should need a linked service or an instance url' do
      subject.valid?
      expect(subject.errors[:forgejo_service_id]).not_to be_empty

      subject.instance_url = 'https://git.example.com/'
      subject.valid?
      expect(subject.errors[:forgejo_service_id]).to be_empty
    end

    it 'should only accept a 40 hex char secret' do
      subject.registration_secret = 'xyz'
      subject.valid?
      expect(subject.errors[:registration_secret]).not_to be_empty

      subject.registration_secret = 'a' * 40
      subject.valid?
      expect(subject.errors[:registration_secret]).to be_empty
    end

    it 'should only accept host labels' do
      subject.labels = ['ubuntu-latest:docker://node:20']
      subject.valid?
      expect(subject.errors[:labels]).not_to be_empty

      subject.labels = ['ubuntu-latest:host', 'build.arm64:host']
      subject.valid?
      expect(subject.errors[:labels]).to be_empty
    end
  end

  describe 'effective_labels' do
    it 'should default to ubuntu-latest and self-hosted on the host executor' do
      expect(subject.effective_labels).to eq ['ubuntu-latest:host', 'self-hosted:host']
      expect(subject.label_names).to eq ['ubuntu-latest', 'self-hosted']
    end

    it 'should use configured labels' do
      subject.labels_list = 'build:host, test:host'
      expect(subject.labels).to eq ['build:host', 'test:host']
      expect(subject.effective_labels).to eq ['build:host', 'test:host']
      expect(subject.labels_list).to eq 'build:host, test:host'
    end
  end

  describe 'runner_uuid' do
    it 'should derive the uuid Forgejo computes from the first 16 chars of the secret (docs example)' do
      subject.registration_secret = '7c31591e8b67225a116d4a4519ea8e507e08f71f'
      expect(subject.runner_uuid).to eq '37633331-3539-3165-3862-363732323561'
    end

    it 'should be nil without a secret' do
      expect(subject.runner_uuid).to be_nil
    end
  end

  describe 'job_environment' do
    it 'should wire the RVM default ruby and a writable bundle path' do
      subject.additional_components = ['ruby@3.4']
      env = subject.job_environment
      expect(env['PATH']).to start_with '/usr/local/rvm/wrappers/default:'
      expect(env['BUNDLE_PATH']).to eq '/var/lib/forgejo-runner/gems'
      expect(env['HOME']).to eq '/var/lib/forgejo-runner'
    end

    it 'should wire the rust tool chain' do
      subject.additional_components = ['rust']
      env = subject.job_environment
      expect(env['PATH']).to include '/usr/local/cargo/bin'
      expect(env['RUSTUP_HOME']).to eq '/usr/local/rustup'
    end

    it 'should fall back to the system path' do
      expect(subject.job_environment['PATH']).to eq '/usr/local/bin:/usr/bin:/bin'
    end
  end

  describe 'effective_instance_url' do
    it 'should prefer the explicit url' do
      subject.instance_url = 'https://git.example.com/'
      expect(subject.effective_instance_url).to eq 'https://git.example.com/'
    end

    it 'should derive the url from the linked service' do
      forgejo = double CloudModel::Services::Forgejo, root_url: 'https://git.linked.example.com/'
      allow(subject).to receive(:forgejo_service).and_return forgejo
      expect(subject.effective_instance_url).to eq 'https://git.linked.example.com/'
    end
  end

  describe 'service_status' do
    let(:guest) { double CloudModel::Guest }
    before { allow(subject).to receive(:guest).and_return guest }

    it 'should report the active daemon' do
      allow(guest).to receive(:exec).with('systemctl is-active forgejo_runner').and_return([true, "active\n"])
      expect(subject.service_status).to eq({state: 'active'})
    end

    it 'should flag an inactive daemon' do
      allow(guest).to receive(:exec).and_return([false, "failed\n"])
      result = subject.service_status
      expect(result[:key]).to eq :inactive
      expect(result[:severity]).to eq :critical
    end
  end
end
