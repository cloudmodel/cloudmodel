# encoding: UTF-8

require 'spec_helper'

describe CloudModel::Monitoring::Services::BaseChecks do
  let(:service) { double CloudModel::Services::Base }
  subject { CloudModel::Monitoring::ServiceChecks.new service, skip_header: true }

  #it { expect(subject).to be_a CloudModel::Monitoring::BaseChecks }
  
  pending
end