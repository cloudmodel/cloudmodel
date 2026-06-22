require 'spec_helper'

describe CloudModel::SolrImageJobs::BuildJob do
  let(:solr_image) { double CloudModel::SolrImage }
  let(:worker) { double CloudModel::Workers::SolrImageWorker }

  it 'finds the solr image, builds a SolrImageWorker and builds it in debug mode' do
    expect(CloudModel::SolrImage).to receive(:find).with('solr-id').and_return(solr_image)
    expect(CloudModel::Workers::SolrImageWorker).to receive(:new).with(solr_image).and_return(worker)
    expect(worker).to receive(:build).with(debug: true)

    subject.perform('solr-id')
  end
end
