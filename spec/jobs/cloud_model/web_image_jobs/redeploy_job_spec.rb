require 'spec_helper'

describe CloudModel::WebImageJobs::RedeployJob do
  let(:web_image) { double CloudModel::WebImage }
  let(:worker) { double CloudModel::Workers::WebImageWorker }

  it 'finds the web image and rolls it out through a worker without a build host' do
    expect(CloudModel::WebImage).to receive(:find).with('web-id').and_return(web_image)
    # the rollout targets each service's own host; the worker needs no build host
    expect(CloudModel::Workers::WebImageWorker).to receive(:new).with(nil, web_image).and_return(worker)
    expect(worker).to receive(:redeploy).with(verbose: true)

    subject.perform('web-id')
  end
end
