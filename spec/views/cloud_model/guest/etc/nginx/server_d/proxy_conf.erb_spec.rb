require 'spec_helper'

RSpec.describe 'cloud_model/guest/etc/nginx/server_d/proxy_conf', type: :view do
  let(:model) { CloudModel::Services::Nginx.new(reverse_proxy_supported: true, reverse_proxy_for: 'http://localhost:8080') }

  it 'proxies / over HTTP/1.1 with the websocket upgrade headers passed on' do
    render template: 'cloud_model/guest/etc/nginx/server_d/proxy_conf', locals: { model: model }

    location = rendered[/location \/ \{.*\}/m]
    expect(location).to include "proxy_http_version 1.1;\n"
    expect(location).to include "proxy_set_header Upgrade $http_upgrade;\n"
    expect(location).to include "proxy_set_header Connection $http_connection;\n"
    expect(location).to include "proxy_pass http://localhost:8080;\n"
  end
end
