# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::LxdCustomVolumeChecks do
  let(:volume) { double CloudModel::LxdCustomVolume }
  subject { CloudModel::Monitoring::LxdCustomVolumeChecks.new volume, skip_header: true }

  it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }
  
  pending
end