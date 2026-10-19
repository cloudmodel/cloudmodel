require 'spec_helper'

describe CloudModel::GuestJobs::RedeployManyJob do
  it 'runs the batch redeploy for the given guests' do
    expect(CloudModel::Guest).to receive(:redeploy_batch!).with(%w[a b c]).and_return(deployed: %w[a b c], failed: {})

    subject.perform(%w[a b c])
  end
end
