require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/default/rails', type: :view do
  it 'renders RAILS_ENV and the passenger env vars, so rake services and delayed jobs share the app environment' do
    model = CloudModel::Services::Nginx.new(passenger_env: 'staging',
      passenger_env_vars: { 'NEEDLE_INDEX_PATH' => '/var/www/shared/needle', 'TANTIVY_INSTANCE_ID' => 'r1-graph05@core05' })
    render template: 'cloud_model/guest/etc/default/rails', locals: { model: model }

    expect(rendered).to eq <<~ENV
      RAILS_ENV=staging
      NEEDLE_INDEX_PATH="/var/www/shared/needle"
      TANTIVY_INSTANCE_ID="r1-graph05@core05"
    ENV
  end

  it 'escapes what the shell would expand' do
    model = CloudModel::Services::Nginx.new(passenger_env: 'production', passenger_env_vars: { 'X' => 'a"b$c`d\\e' })
    render template: 'cloud_model/guest/etc/default/rails', locals: { model: model }

    expect(rendered).to include 'X="a\\"b\\$c\\`d\\\\e"'
  end

  it 'renders only RAILS_ENV without env vars' do
    render template: 'cloud_model/guest/etc/default/rails', locals: { model: CloudModel::Services::Nginx.new(passenger_env: 'production') }
    expect(rendered).to eq "RAILS_ENV=production\n"
  end
end
