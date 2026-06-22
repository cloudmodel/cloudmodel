require 'spec_helper'

describe CloudModel::WebImageJobs::BuildJob do
  let(:web_image) { double CloudModel::WebImage }
  let(:worker) { double CloudModel::Workers::WebImageWorker }

  it 'finds the web image, builds a WebImageWorker and builds it' do
    expect(CloudModel::WebImage).to receive(:find).with('web-id').and_return(web_image)
    expect(CloudModel::Workers::WebImageWorker).to receive(:new).with(web_image).and_return(worker)
    expect(worker).to receive(:build)

    subject.perform('web-id')
  end
end
