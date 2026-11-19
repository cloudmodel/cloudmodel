require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/sites-available/cloudmodel_conf', type: :view do
  let(:host) { CloudModel::Host.new }
  let(:guest) { CloudModel::Guest.new host: host, external_hostname: 'www.example.com' }
  let(:model) { CloudModel::Services::Nginx.new guest: guest, ssl_supported: true, ssl_cert: CloudModel::Certificate.new }

  def render_conf
    render template: 'cloud_model/guest/etc/nginx/sites-available/cloudmodel_conf', locals: { guest: guest, model: model, certbot_cert_available: false }
  end

  it 'renders the TLS listener with HTTP/2 by default' do
    render_conf

    expect(rendered).to match(/^\s*listen\s+443 ssl http2 deferred;$/)
    expect(rendered).to match(/^\s*listen\s+80;$/)
  end

  it 'renders the request body limit in megabytes, 0 as unlimited' do
    render_conf
    expect(rendered).to match(/^\s*client_max_body_size\s+600M;$/)

    model.client_max_body_size = 0
    render_conf
    expect(rendered).to match(/^\s*client_max_body_size\s+0;$/)
  end

  it 'renders the TLS listener without HTTP/2 when the option is off' do
    model.http2 = false
    render_conf

    expect(rendered).to match(/^\s*listen\s+443 ssl deferred;$/)
    expect(rendered).not_to include 'http2'
  end
end
