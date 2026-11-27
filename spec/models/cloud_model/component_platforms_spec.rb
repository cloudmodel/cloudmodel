# encoding: UTF-8

require 'spec_helper'

describe CloudModel::ComponentPlatforms do
  let(:table) do
    {
      'mongodb' => { '7.0' => { 'debian-12' => %w(amd64), 'ubuntu-22.04' => %w(amd64 arm64) }, '8.0' => { 'ubuntu-22.04' => %w(amd64 arm64) } },
      'percona_server_mongodb' => { '8.0' => { 'debian-13' => %w(amd64 arm64) } }
    }
  end
  before { allow(described_class).to receive(:table).and_return table }

  it 'ships a table for every probed component' do
    allow(described_class).to receive(:table).and_call_original
    described_class.reload!
    expect(described_class.table.keys).to match_array described_class::PROBES.keys
  end

  describe '.os_key' do
    it 'maps point releases onto the release' do
      expect(described_class.os_key('ubuntu-22.04.4')).to eq 'ubuntu-22.04'
      expect(described_class.os_key('debian-13')).to eq 'debian-13'
      expect(described_class.os_key('ubuntu-26.04')).to be_nil
    end
  end

  describe '.supported?' do
    it 'knows published and missing combinations' do
      expect(described_class.supported?(:mongodb, '7.0', 'debian-12', 'amd64')).to eq true
      expect(described_class.supported?(:mongodb, '7.0', 'debian-12', 'arm64')).to eq false
      expect(described_class.supported?(:mongodb, '8.0', 'debian-13', 'amd64')).to eq false
    end

    it 'does not restrict what the table does not know' do
      expect(described_class.supported?(:fuseki, '5', 'debian-12', 'amd64')).to be_nil
      expect(described_class.supported?(:mongodb, '8.0', 'ubuntu-26.04', 'amd64')).to be_nil
      expect(described_class.supported?(:mongodb, '8.0', 'debian-12', nil)).to be_nil
    end
  end

  describe '.lines' do
    it 'lists the lines for an OS and arch' do
      expect(described_class.lines(:mongodb, 'ubuntu-22.04.4', 'arm64')).to eq %w(7.0 8.0)
      expect(described_class.lines(:mongodb, 'debian-13', 'amd64')).to eq []
      expect(described_class.lines(:percona_server_mongodb, 'debian-13', 'arm64')).to eq %w(8.0)
    end
  end

  describe '.index_has_package?' do
    it 'finds the package in a plain or gzipped index' do
      body = "Package: other\nVersion: 1\n\nPackage: mongodb-org-server\nVersion: 8.0.38\n"
      allow(Net::HTTP).to receive(:get_response).and_return(double(body: Zlib.gzip(body)).tap { |r| allow(r).to receive(:is_a?).with(Net::HTTPSuccess).and_return true })
      expect(described_class.index_has_package?('https://example.org/Packages.gz', 'mongodb-org-server')).to eq true
      expect(described_class.index_has_package?('https://example.org/Packages.gz', 'mongodb-org')).to eq false
    end
  end
end
