# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::ServiceChecks do
  let(:host) {double CloudModel::Host, name: 'testhost'}
  let(:guest) { double CloudModel::Guest, host: host }
  let(:service) { double CloudModel::Services::Base, guest: guest }

  subject { CloudModel::Monitoring::ServiceChecks.new service, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }

  describe 'indent_size' do
    it 'should indent by 2' do
      expect(subject.indent_size).to eq 2
    end
  end

  describe 'line_prefix' do
    it 'should prefix host name before indention' do
      expect(subject.line_prefix).to eq '[testhost]   '
    end
  end

  describe 'data' do
    pending
  end

  describe 'check' do
    pending
  end
end