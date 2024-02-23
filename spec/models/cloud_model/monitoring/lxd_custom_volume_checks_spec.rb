# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::LxdCustomVolumeChecks do
  let(:host) {double CloudModel::Host, name: 'testhost'}
  let(:guest) { double CloudModel::Guest, host: host }
  let(:volume) { double CloudModel::LxdCustomVolume, guest: guest }
  subject { CloudModel::Monitoring::LxdCustomVolumeChecks.new volume, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe 'indent_size' do
    it 'should indent by 4' do
      expect(subject.indent_size).to eq 4
    end
  end

  describe 'line_prefix' do
    it 'should prefix host name before indention' do
      expect(subject.line_prefix).to eq '[testhost]     '
    end
  end

  describe 'acquire_data' do
    it 'should return lxc_show on subject' do
      lxc_info = double
      expect(volume).to receive(:lxc_show).and_return lxc_info
      expect(subject.acquire_data).to eq lxc_info
    end
  end

  describe 'check_existence' do
    it 'check if volume exists, returning true' do
      allow(volume).to receive(:volume_exists?).and_return true
      allow(subject).to receive(:data).and_return "some"=>"info"
      expect(subject).to receive(:do_check).with(
        :existence,
        'existence of volume',
        warning: false
      )
      subject.check_existence
    end

    it 'check if volume exists, returning false' do
      allow(volume).to receive(:volume_exists?).and_return false
      allow(subject).to receive(:data).and_return "error"=>"not found"
      expect(subject).to receive(:do_check).with(
        :existence,
        'existence of volume',
        warning: true
      )
      subject.check_existence
    end
  end

  describe 'check' do
    it 'should call existence check' do
      expect(subject).to receive(:data)
      expect(subject).to receive(:check_existence)
      subject.check
    end
  end
end