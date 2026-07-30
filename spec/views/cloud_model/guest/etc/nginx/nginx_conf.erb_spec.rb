require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/nginx_conf', type: :view do
  let(:model) { CloudModel::Services::Nginx.new }

  it 'renders the timing log format' do
    render template: 'cloud_model/guest/etc/nginx/nginx_conf', locals: { model: model }

    expect(rendered).to include "log_format                    timing  '$msec $status $request_time $upstream_response_time \"$request\"';"
    expect(rendered).to include 'access_log                    /var/log/nginx/timing.log  timing;'
  end

  it 'omits the passenger pool size without passenger' do
    render template: 'cloud_model/guest/etc/nginx/nginx_conf', locals: { model: model }

    expect(rendered).not_to include 'passenger_max_pool_size'
  end

  it 'renders the configured passenger pool size with passenger' do
    model.passenger_supported = true
    model.passenger_max_pool_size = 12

    render template: 'cloud_model/guest/etc/nginx/nginx_conf', locals: { model: model }

    expect(rendered).to include 'passenger_max_pool_size       12;'
  end
end
