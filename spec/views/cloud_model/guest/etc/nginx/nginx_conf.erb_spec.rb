require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/nginx_conf', type: :view do
  let(:guest) { CloudModel::Guest.new cpu_count: 2 }
  let(:model) { CloudModel::Services::Nginx.new guest: guest }

  def render_conf
    render template: 'cloud_model/guest/etc/nginx/nginx_conf', locals: { guest: guest, model: model }
  end

  it 'renders the timing log format' do
    render_conf

    expect(rendered).to include "log_format                    timing  '$msec $status $request_time $upstream_response_time \"$request\"';"
    expect(rendered).to include 'access_log                    /var/log/nginx/timing.log  timing;'
  end

  it 'sizes the worker processes to the CPUs of the guest' do
    guest.cpu_count = 4
    render_conf

    expect(rendered).to match(/^worker_processes\s+4;$/)
  end

  it 'keeps one worker for a guest without a CPU count' do
    guest.cpu_count = nil
    render_conf

    expect(rendered).to match(/^worker_processes\s+1;$/)
  end

  it 'omits the passenger pool size without passenger' do
    render_conf

    expect(rendered).not_to include 'passenger_max_pool_size'
  end

  it 'renders the configured passenger pool size with passenger' do
    model.passenger_supported = true
    model.passenger_max_pool_size = 12
    render_conf

    expect(rendered).to include 'passenger_max_pool_size       12;'
  end
end
