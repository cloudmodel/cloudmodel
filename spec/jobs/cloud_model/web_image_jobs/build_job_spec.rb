require 'spec_helper'

describe CloudModel::WebImageJobs::BuildJob do
  let(:web_image) { double CloudModel::WebImage }
  let(:worker) { double CloudModel::Workers::WebImageWorker }

  it 'finds the web image and runs its (per-arch) build, forced past the buildable guard' do
    expect(CloudModel::WebImage).to receive(:find).with('web-id').and_return(web_image)
    # build! fans out to a build host per arch itself — no single worker here
    expect(CloudModel::Workers::WebImageWorker).not_to receive(:new)
    expect(web_image).to receive(:build!).with(force: true)

    subject.perform('web-id')
  end
end
